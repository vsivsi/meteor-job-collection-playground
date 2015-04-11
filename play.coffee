############################################################################
#     Copyright (C) 2015 by Vaughn Iverson
#     meteor-job-collection-playground is free software released under the MIT/X11 license.
#     See included LICENSE file for details.
############################################################################

myJobs = new JobCollection 'queue',
   idGeneration: 'MONGO'
   transform: (d) ->
      try
         res = new Job myJobs, d
      catch e
         res = d
      return res

later = myJobs.later

Router.configure
   layoutTemplate: 'master'

Router.route '/', () ->

   this.render 'jobTable',
      to: 'content'
      data: myJobs

if Meteor.isClient

   parseState = new ReactiveVar("")
   parseSched = new ReactiveVar([])
   reactiveDate = new ReactiveVar(new Date())
   later.date.localTime()

   Meteor.setInterval((() -> reactiveDate.set new Date()), 5000)

   q = null
   myType = 'testJob_null'

   Tracker.autorun () ->
      userId = Meteor.userId()
      suffix = if userId then "_#{userId.substr(0,5)}" else ""
      myType = "testJob#{suffix}"
      Meteor.subscribe 'allJobs', userId
      q?.shutdown { level: 'hard' }
      q = myJobs.processJobs myType, { pollInterval: 100000000 }, (job, cb) ->
         count = 0
         int = Meteor.setInterval (() ->
            count++
            if count is 20
               Meteor.clearInterval int
               job.done()
               cb()
            else
               job.progress count, 20, (err, res) ->
                  if err or not res
                     Meteor.clearInterval int
                     job.fail('Progress update failed', () -> cb())
         ), 500
      obs = myJobs.find({ type: myType, status: 'ready' })
      .observe
         added: () -> q.trigger()

   Template.top.helpers
      userId: () ->
         Meteor.userId()

   Template.jobTable.helpers

      jobEntries: () ->
         # Reactively populate the table
         this.find({}, { sort: { after: -1 }})

   Template.jobEntry.rendered = () ->
      this.$('.button-column').tooltip
         selector: 'button[data-toggle=tooltip]'
         delay:
            show: 500
            hide: 100

   Template.jobEntry.events
      'click .cancel-job': (e, t) ->
         job = Template.currentData()
         job.cancel() if job
      'click .remove-job': (e, t) ->
         job = Template.currentData()
         job.remove() if job
      'click .restart-job': (e, t) ->
         job = Template.currentData()
         job.restart() if job
      'click .rerun-job': (e, t) ->
         job = Template.currentData()
         job.rerun({ wait: 15000 }) if job
      'click .pause-job': (e, t) ->
         job = Template.currentData()
         job.pause() if job
      'click .resume-job': (e, t) ->
         job = Template.currentData()
         job.resume() if job

   isInfinity = (val) ->
      if val > Job.forever - 7199254740935
         "∞"
      else
         val

   Template.jobEntry.helpers

      jobId: () ->
         "#{this._id.valueOf().substr(0,5)}…"

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

      numRepeats: () -> isInfinity this.repeats

      numRetries: () -> isInfinity this.retries

      runAt: () ->
         reactiveDate.get()
         moment(this.after).fromNow()

      lastUpdated: () ->
         reactiveDate.get()
         moment(this.updated).fromNow()

      futurePast: () ->
         reactiveDate.get()
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
         this.status in Job.jobStatusCancellable

      removable: () ->
         this.status in Job.jobStatusRemovable

      restartable: () ->
         this.status in Job.jobStatusRestartable

      rerunable: () ->
         this.status is 'completed'

      pausable: () ->
         this.status in Job.jobStatusPausable

      resumable: () ->
         this.status is 'paused'

   Template.newJobInput.helpers

      inputParseState: () ->
         parseState.get()

      inputReady: () ->
         parseState.get() is "has-success"

      nextTimes: () ->
         reactiveDate.get()
         for t in parseSched.get().next(3)
            "#{moment(t).format("dddd, MMMM Do YYYY, h:mm:ss")} (#{moment(t).fromNow()})"

   Template.newJobInput.events

      'input #inputLater': (e, t) ->
         val = e.target.value.trim() 
         unless val
            parseState.set ""
            parseSched.set []
         else
            s = later.parse.text val
            if s.error is -1
               parseState.set "has-success"
               parseSched.set later.schedule(s)
            else
               re = /^(?:\*|\d{1,2})(?:(?:(?:[\/-]\d{1,2})?)|(?:,\d{1,2})+)\ *(?:\ (?:\*|\d{1,2})(?:(?:(?:[\/-]\d{1,2})?)|(?:,\d{1,2})+)\ *)*$/
               m = val.match re
               sp = val.split /\ +/ 

               if m and 5 <= sp.length <= 6 
                  sCron = later.parse.cron val, sp.length is 6
                  if sCron
                     parseState.set "has-success"
                     parseSched.set later.schedule(sCron)
                  else
                     parseState.set parseState.set "has-warning"
                     parseSched.set []
               else
                  parseState.set "has-warning"
                  parseSched.set []

      'click #newJob': (e, t) ->
         s = later.parse.text(t.find("#inputLater").value)
         if s.error is -1
            job = new Job(myJobs, myType, { owner: Meteor.userId() })
               .retry({ retries: 3, wait: 30000, backoff: 'exponential'})
               .repeat({ schedule: s })
               .save({cancelRepeats: true})
         else
            parseState.set "has-error"

   Template.jobControls.events

      'click .clear-completed': (e, t) ->
         ids = t.data.find({ status: 'completed' },{ fields: { _id: 1 }}).map (d) -> d._id
         t.data.removeJobs(ids) if ids.length > 0

      'click .pause-queue': (e, t) ->
         if $(e.target).hasClass 'active'
            ids = t.data.find({ status: 'paused' },{ fields: { _id: 1 }}).map (d) -> d._id
            t.data.resumeJobs(ids) if ids.length > 0
         else
            ids = t.data.find({ status: { $in: Job.jobStatusPausable }}, { fields: { _id: 1 }}).map (d) -> d._id
            t.data.pauseJobs(ids) if ids.length > 0

      'click .cancel-queue': (e, t) ->
         ids = t.data.find({ status: { $in: Job.jobStatusCancellable }}, { fields: { _id: 1 }}).map (d) -> d._id
         t.data.cancelJobs(ids) if ids.length > 0

      'click .restart-queue': (e, t) ->
         ids = t.data.find({ status: { $in: Job.jobStatusRestartable }}, { fields: { _id: 1 }}).map (d) -> d._id
         t.data.restartJobs(ids) if ids.length > 0

      'click .remove-queue': (e, t) ->
         ids = t.data.find({ status: { $in: Job.jobStatusRemovable }}, { fields: { _id: 1 }}).map (d) -> d._id
         t.data.removeJobs(ids) if ids.length > 0

#######################################################

if Meteor.isServer

   # myJobs.setLogStream process.stdout
   myJobs.promote 5000

   Meteor.startup () ->

      # Don't allow users to modify the user docs
      Meteor.users.deny({update: () -> true })

      myJobs.startJobServer()

      Meteor.publish 'allJobs', (clientUserId) ->
         # This prevents a race condition on the client between Meteor.userId() and subscriptions to this publish
         # See: https://stackoverflow.com/questions/24445404/how-to-prevent-a-client-reactive-race-between-meteor-userid-and-a-subscription/24460877#24460877
         if this.userId is clientUserId
            suffix = if this.userId then "_#{this.userId.substr(0,5)}" else ""
            return myJobs.find({ type: "testJob#{suffix}", 'data.owner': this.userId })
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

         jobSave: (userId, method, params) ->
            doc = params[0]
            return doc.data.owner is userId

         getWork: (userId, method, params) ->
            suffix = if userId then "_#{userId.substr(0,5)}" else ""
            params[0][0] is "testJob#{suffix}" and params[0].length is 1

         worker: (userId, method, params) ->
            if method is 'getWork'
               return false
            else
               id = params[0]
               numMatches = myJobs.find({ _id: id, 'data.owner': userId }).count()
               return numMatches is 1

      new Job(myJobs, 'cleanup', {})
         .repeat({ schedule: myJobs.later.parse.text("every 5 minutes") })
         .save({cancelRepeats: true})

      new Job(myJobs, 'autofail', {})
         .repeat({ schedule: myJobs.later.parse.text("every 1 minute") })
         .save({cancelRepeats: true})

      q = myJobs.processJobs ['cleanup', 'autofail'], { pollInterval: 100000000 }, (job, cb) ->
         current = new Date()
         switch job.type
            when 'cleanup'
               current.setMinutes(current.getMinutes() - 5)
               ids = myJobs.find({
                  status:
                     $in: Job.jobStatusRemovable
                  updated:
                     $lt: current},
                  {fields: { _id: 1 }}).map (d) -> d._id
               myJobs.removeJobs(ids) if ids.length > 0
               # console.warn "Removed #{ids.length} old jobs"
               job.done("Removed #{ids.length} old jobs")
               cb()
            when 'autofail'
               c = 0
               current.setMinutes(current.getMinutes() - 1)
               myJobs.find({
                  status: 'running'
                  updated:
                     $lt: current})
               .forEach (j) ->
                  c++
                  j.fail('Timed out by autofail')
               # console.warn "Failed #{c} stale running jobs"
               job.done("Failed #{c} stale running jobs")
               cb()
            else
               job.fail "Bad job type in worker"
               cb()

      myJobs.find({ type: { $in: ['cleanup', 'autofail']}, status: 'ready' })
         .observe
            added: () -> q.trigger()
