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

if Meteor.isClient

   stats = new Mongo.Collection 'jobStats'
   Meteor.subscribe 'clientStats'

   jobsProcessed = new ReactiveVar(0)
   reactiveWindowWidth = new ReactiveVar(0)

   Meteor.startup () ->
      timeout = null
      reactiveWindowWidth.set $(window).width()
      $(window).resize () ->
         Meteor.clearTimeout(timeout) if timeout
         timeout = Meteor.setTimeout () ->
               timeout = null
               reactiveWindowWidth.set $(window).width()
            , 100

   parseState = new ReactiveVar ""
   parseSched = new ReactiveVar []
   reactiveDate = new ReactiveVar new Date()
   localWorker = new ReactiveVar null

   Meteor.setInterval((() -> reactiveDate.set new Date()), 5000)

   q = null
   myType = 'testJob_null'

   Tracker.autorun () ->
      userId = Meteor.userId()
      suffix = if userId then "_#{userId.substr(0,5)}" else ""
      myType = "testJob#{suffix}"
      Meteor.subscribe 'allJobs', userId
      q?.shutdown { level: 'hard' }
      q = myJobs.processJobs myType, { pollInterval: false, workTimeout: 60*1000 }, (job, cb) ->
         done = 0
         localWorker.set job.doc
         int = Meteor.setInterval (() ->
            lw = localWorker.get()
            if lw
               done++
               if done is 20
                  Meteor.clearInterval int
                  localWorker.set null
                  jobsProcessed.set jobsProcessed.get() + 1
                  job.done()
                  cb()
               else
                  job.progress done, 20, (err, res) ->
                     if err or not res
                        Meteor.clearInterval int
                        localWorker.set null
                        job.fail('Progress update failed', () -> cb())
                     else
                        localWorker.set job.doc
            else if lw is null
               Meteor.clearInterval int
               job.fail('User aborted job', () -> cb())
            else
               # Simulate a crash
               Meteor.clearInterval int
               cb()  # Return without .done or .fail, creating a zombie
         ), 500
      obs = myJobs.find({ type: myType, status: 'ready' })
      .observe
         added: () -> q.trigger()

   Template.registerHelper "jobCollection", () -> myJobs

   Template.registerHelper "localWorker", () -> localWorker.get()

   Template.registerHelper "wideScreen", () -> reactiveWindowWidth.get() > 1745

   Template.registerHelper "relativeTime", (time) ->
      now = reactiveDate.get()
      moment(time).from(now)

   Template.registerHelper "equals", (a, b) -> a is b

   truncateId = (id, length = 6) ->
      if id
         if typeof id is 'object'
            id = "#{id.valueOf()}"
         "#{id.substr(0,6)}…"
      else
         ""

   Template.registerHelper "truncateId", truncateId

   Template.top.helpers
     userId: () ->
       Meteor.userId()

     clientsConnected: () ->
        return stats.findOne('stats').currentClients

   Template.workerPanel.helpers
      jobsProcessed: () ->
         return jobsProcessed.get()

   Template.workerPanel.events
      'click .fail-job': (e, t) ->
         localWorker.set null
      'click .crash-job': (e, t) ->
         localWorker.set false

   Template.jobTable.helpers
      jobEntries: () ->
         # Reactively populate the table
         this.find({}, { sort: { after: -1 }})
      jobsProcessed: () ->
         return stats.findOne('stats').jobsProcessed
      numWorkers: () ->
         return stats.findOne('stats').clientsSeen

   handleButtonPopup = () ->
      this.$('.button')
         .popup
            inline: true
            position: 'bottom center'
            delay:
               show: 500
               hide: 0

   Template.pauseButton.onRendered handleButtonPopup
   Template.removeButton.onRendered handleButtonPopup
   Template.resumeButton.onRendered handleButtonPopup
   Template.restartButton.onRendered handleButtonPopup
   Template.rerunButton.onRendered handleButtonPopup
   Template.cancelButton.onRendered handleButtonPopup
   Template.readyNowButton.onRendered handleButtonPopup

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
      'click .ready-job': (e, t) ->
         job = Template.currentData()
         job.ready({ time: myJobs.foreverDate }) if job

   isInfinity = (val) ->
      if val > Job.forever - 7199254740935
         "∞"
      else
         val

   Template.jobEntry.helpers

      statusBG: () ->
         {
           waiting: 'grey'
           ready: 'blue'
           paused: 'black'
           running: 'default'
           cancelled: 'yellow'
           failed: 'red'
           completed: 'green'
         }[this.status]

      numRepeats: () -> isInfinity this.repeats

      numRetries: () -> isInfinity this.retries

      futurePast: () ->
         now = reactiveDate.get()
         if this.after > now
            "text-danger"
         else
            "text-success"

      cancellable: () ->
         this.status in Job.jobStatusCancellable

      removable: () ->
         this.status in Job.jobStatusRemovable

      restartable: () ->
         this.status in Job.jobStatusRestartable

      pausable: () ->
         this.status in Job.jobStatusPausable

   Template.newJobInput.helpers

      inputParseState: () ->
         parseState.get()

      inputReady: () ->
         parseState.get() is "has-success"

      inputError: () ->
        if parseState.get() is "has-error"
          "error"
        else
          ""

      nextTimes: () ->
         reactiveDate.get()
         for t in parseSched.get().next(3)
            "#{moment(t).calendar()} (local time), #{moment(t).fromNow()}. [#{moment(t).toISOString()}]"

   Template.logEntries.helpers
      recentEvents: (numEvents = 5) ->
         output = []
         this.find({}, { fields: { log: 1, type: 1 }, transform: null, limit: numEvents, sort: { updated: -1 }})
            .forEach (doc) ->
               for event in doc.log
                  event.type = doc.type
                  event.jobId = truncateId doc._id
                  event.runId = truncateId event.runId
                  event.level = "error" if event.level is 'danger'
                  output.push event
         output.sort (a, b) ->
            b.time - a.time
         output.slice 0, numEvents

      levelIcon: () ->
         switch this.level
            when 'info' then 'info'
            when 'success' then 'trophy'
            when 'warning' then 'warning sign'
            when 'error' then 'thumbs down'
            else 'bug'

   validateCRON = (val) ->
      re = /^(?:\*|\d{1,2})(?:(?:(?:[\/-]\d{1,2})?)|(?:,\d{1,2})+)\ *(?:\ (?:\*|\d{1,2})(?:(?:(?:[\/-]\d{1,2})?)|(?:,\d{1,2})+)\ *)*$/
      return null unless val.match re
      sp = val.split /\ +/
      if 5 <= sp.length <= 6
         return sp.length is 6
      else
         return null

   newJobSubmit = (e, t) ->
      val = t.find("#inputLater").value
      cronFlag = validateCRON val
      if cronFlag?
         s = later.parse.cron val, cronFlag
         s.error = -1 if s?
      else
         s = later.parse.text(val)
      if s.error is -1
         job = new Job(myJobs, myType, { owner: Meteor.userId() })
            .retry({ retries: 2, wait: 30000, backoff: 'exponential'})
            .repeat({ schedule: s })
            .save({cancelRepeats: true})
      else
         parseState.set "has-error"

   Template.newJobInput.events

      'click #newJob': newJobSubmit

      'keyup #inputLater': (e, t) ->
        if e.keyCode is 13
           newJobSubmit e, t

      'input #inputLater': (e, t) ->
         val = e.target.value.trim()
         unless val
            parseState.set ""
            parseSched.set []
         else
            s = later.parse.text val
            # The following is to work around this bug:
            # https://github.com/bunkat/later/issues/97
            try
               later.schedule(s).next()
            catch
               s = {}
            if s.error is -1
               parseState.set "has-success"
               parseSched.set later.schedule(s)
            else
               cronFlag = validateCRON val
               if cronFlag?
                  sCron = later.parse.cron val, cronFlag
                  if sCron
                     parseState.set "has-success"
                     parseSched.set later.schedule(sCron)
                  else
                     parseState.set parseState.set "has-warning"
                     parseSched.set []
               else
                  parseState.set "has-warning"
                  parseSched.set []

   Template.jobControls.events

      'click .pause-queue': (e, t) ->
         if $(e.target).hasClass 'active'
            $(e.target).removeClass 'active'
            ids = t.data.find({ status: 'paused' },{ fields: { _id: 1 }}).map (d) -> d._id
            t.data.resumeJobs(ids) if ids.length > 0
         else
            $(e.target).addClass 'active'
            ids = t.data.find({ status: { $in: Job.jobStatusPausable }}, { fields: { _id: 1 }}).map (d) -> d._id
            t.data.pauseJobs(ids) if ids.length > 0

      'click .cancel-queue': (e, t) ->
         ids = t.data.find({ status: { $in: Job.jobStatusCancellable }}, { fields: { _id: 1 }}).map (d) -> d._id
         t.data.cancelJobs(ids) if ids.length > 0

      'click .restart-queue': (e, t) ->
         ids = t.data.find({ status: { $in: Job.jobStatusRestartable }}, { fields: { _id: 1 }}).map (d) -> d._id
         t.data.restartJobs(ids) if ids.length > 0

      'click .rerun-queue': (e, t) ->
         t.data.find({ status: 'completed' }).forEach (d) ->
           d.rerun { wait: 15000 }

      'click .remove-queue': (e, t) ->
         ids = t.data.find({ status: { $in: Job.jobStatusRemovable }}, { fields: { _id: 1 }}).map (d) -> d._id
         t.data.removeJobs(ids) if ids.length > 0

#######################################################

if Meteor.isServer

   myJobs.setLogStream process.stdout
   myJobs.promote 5000

   Meteor.startup () ->

      jobsProcessed = 0
      clientsSeen = {}
      currentClients = {}

      # Don't allow users to modify the user docs
      Meteor.users.deny({update: () -> true })

      myJobs.startJobServer()

      Meteor.publish 'clientStats', () ->
         currentClients[@connection.id] = () =>
            @changed 'jobStats', 'stats',
               jobsProcessed: jobsProcessed
               clientsSeen: Object.keys(clientsSeen).length
               currentClients: Object.keys(currentClients).length
         @added 'jobStats', 'stats',
            jobsProcessed: jobsProcessed
            clientsSeen: Object.keys(clientsSeen).length
            currentClients: Object.keys(currentClients).length
         @onStop () =>
            delete currentClients[@connection.id]
         @ready()

      Meteor.publish 'allJobs', (clientUserId) ->
         # This prevents a race condition on the client between Meteor.userId() and subscriptions to this publish
         # See: https://stackoverflow.com/questions/24445404/how-to-prevent-a-client-reactive-race-between-meteor-userid-and-a-subscription/24460877#24460877
         if this.userId is clientUserId
            suffix = if this.userId then "_#{this.userId.substr(0,5)}" else ""
            return myJobs.find({ type: "testJob#{suffix}", 'data.owner': this.userId })
         else
            return []

      myJobs.events.on 'jobDone', (msg) ->
         unless msg.error or not connection
            jobsProcessed++
            clientsSeen[msg.connection.id] ?= 0
            clientsSeen[msg.connection.id]++
            console.warn "Jobs processed: #{jobsProcessed} #{Object.keys(clientsSeen).length}"
            f() for c, f of currentClients

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

      q = myJobs.processJobs 'cleanup', { pollInterval: false, workTimeout: 60*1000 }, (job, cb) ->
         current = new Date()
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

      myJobs.find({ type: 'cleanup', status: 'ready' })
         .observe
            added: () ->
               q.trigger()
