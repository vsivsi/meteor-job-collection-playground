myJobs = new JobCollection 'queue',
   idGeneration: 'MONGO'
   transform: (d) ->
      try
         res = new Job myJobs, d
      catch e
         res = d
      return res

Router.configure
   layoutTemplate: 'master'

Router.route '/', () ->

   this.render 'jobTable',
      to: 'content'
      data: myJobs

if Meteor.isClient

   Tracker.autorun () ->
      userId = Meteor.userId()
      Meteor.subscribe 'allJobs', userId


   Template.jobTable.helpers
      jobEntries: () ->
         # Reactively populate the table
         this.find({})

   Template.jobEntry.rendered = () ->
      this.$('.button-column').tooltip({selector: 'button[data-toggle=tooltip]'})

   Template.jobEntry.events
      'click .cancel-job': (e, t) ->
         console.log "Cancelling job: #{this._id}", t
         job = Template.currentData()
         job.cancel() if job
      'click .remove-job': (e, t) ->
         console.log "Removing job: #{this._id}"
         job = Template.currentData()
         job.remove() if job
      'click .restart-job': (e, t) ->
         console.log "Restarting job: #{this._id}"
         job = Template.currentData()
         job.restart() if job
      'click .rerun-job': (e, t) ->
         console.log "Rerunning job: #{this._id}"
         job = Template.currentData()
         job.rerun({ wait: 15000 }) if job
      'click .pause-job': (e, t) ->
         console.log "Pausing job: #{this._id}"
         job = Template.currentData()
         job.pause() if job
      'click .resume-job': (e, t) ->
         console.log "Resuming job: #{this._id}"
         job = Template.currentData()
         job.resume() if job

   Template.jobEntry.helpers
      numDepends: () ->
         this.depends?.length

      numResolved: () ->
         this.resolved?.length

      jobId: () ->
         this._id.valueOf()

      statusBG: () ->
         {
            waiting: 'primary'
            ready: 'info'
            paused: 'default'
            running: 'default'
            cancelled: 'warning'
            failed: 'danger'
            completed: 'success'
         }[this.status]

      numRepeats: () ->
         if this.repeats is parent.Forever
            "∞"
         else
            this.repeats

      numRetries: () ->
         if this.retries is parent.Forever
            "∞"
         else
            this.retries

      runAt: () ->
         Session.get 'date'
         moment(this.after).fromNow()

      lastUpdated: () ->
         Session.get 'date'
         moment(this.updated).fromNow()

      futurePast: () ->
         Session.get 'date'
         if this.after > new Date()
            "text-danger"
         else
            "text-success"

      running: () ->
         if Template.instance().view.isRendered
            # This code destroys Bootstrap tooltips on existing buttons that may be
            # about to disappear. This is done here because by the time the template
            # autorun function runs, the button may already be out of the DOM, but
            # a "ghost" tooltip for that button can remain visible.
            Template.instance().$("button[data-toggle=tooltip]").tooltip('destroy')

         this.status is 'running'

      cancellable: () ->
         this.status in Template.parentData(2).jobStatusCancellable

      removable: () ->
         this.status in Template.parentData(2).jobStatusRemovable

      restartable: () ->
         this.status in Template.parentData(2).jobStatusRestartable

      rerunable: () ->
         this.status is 'completed'

      pausable: () ->
         this.status in Template.parentData(2).jobStatusPausable

      resumable: () ->
         this.status is 'paused'

   Template.jobControls.events

      'click .new-job': (e, t) ->
         console.log 'new job', t.find("#inputLater").value

      'click .clear-completed': (e, t) ->
         console.log "clear completed"
         ids = t.data.find({ status: 'completed' },{ fields: { _id: 1 }}).map (d) -> d._id
         console.log "clearing: #{ids.length} jobs"
         t.data.removeJobs(ids) if ids.length > 0

      'click .pause-queue': (e, t) ->
         if $(e.target).hasClass 'active'
            console.log "resume queue"
            ids = t.data.find({ status: 'paused' },{ fields: { _id: 1 }}).map (d) -> d._id
            console.log "resuming: #{ids.length} jobs"
            t.data.resumeJobs(ids) if ids.length > 0
         else
            console.log "pause queue"
            ids = t.data.find({ status: { $in: t.data.jobStatusPausable }}, { fields: { _id: 1 }}).map (d) -> d._id
            console.log "pausing: #{ids.length} jobs"
            t.data.pauseJobs(ids) if ids.length > 0

      'click .stop-queue': (e, t) ->
         unless $(e.target).hasClass 'active'
            console.log "stop queue"
            t.data.stopJobs()
         else
            console.log "restart queue"
            t.data.stopJobs(0)

      'click .cancel-queue': (e, t) ->
         console.log "cancel all"
         ids = t.data.find({ status: { $in: t.data.jobStatusCancellable } }).map (d) -> d._id
         console.log "cancelling: #{ids.length} jobs"
         t.data.cancelJobs(ids) if ids.length > 0

      'click .restart-queue': (e, t) ->
         console.log "restart all"
         ids = t.data.find({ status: { $in: t.data.jobStatusRestartable } }).map (d) -> d._id
         console.log "restarting: #{ids.length} jobs"
         t.data.restartJobs(ids, (e, r) -> console.log("Restart returned", r)) if ids.length > 0

      'click .remove-queue': (e, t) ->
         console.log "remove all"
         ids = t.data.find({ status: { $in: t.data.jobStatusRemovable } }).map (d) -> d._id
         console.log "removing: #{ids.length} jobs"
         t.data.removeJobs(ids) if ids.length > 0

#######################################################

if Meteor.isServer

   myJobs.setLogStream process.stdout
   myJobs.promote 2500

   Meteor.startup () ->

      # Don't allow users to modify the user docs
      Meteor.users.deny({update: () -> true })

      myJobs.startJobServer()

      Meteor.publish 'allJobs', (clientUserId) ->
         # This prevents a race condition on the client between Meteor.userId() and subscriptions to this publish
         # See: https://stackoverflow.com/questions/24445404/how-to-prevent-a-client-reactive-race-between-meteor-userid-and-a-subscription/24460877#24460877
         if this.userId is clientUserId
            return myJobs.find({ 'data.owner': this.userId })
         else
            return []

      # Only allow job owners to manage or rerun jobs
      myJobs.allow
         manager: (userId, method, params) ->
            ids = params[0]
            unless typeof ids is 'object' and ids instanceof Array
               ids = [ ids ]
            numIds = ids.length
            numMatches = myJobs.find({ _id: { $in: ids }, 'data.owner': userId }).count()
            return numMatches is numIds

         jobRerun: (userId, method, params) ->
            id = params[0]
            numMatches = myJobs.find({ _id: id, 'data.owner': userId }).count()
            return numMatches is 1

         stopJobs: (userId, method, params) ->
            return userId?

