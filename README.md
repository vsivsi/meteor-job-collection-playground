## Meteor job-collection Playground App

This Meteor.js app demonstrates a simple UI on top of the [job-collection](https://atmospherejs.com/vsivsi/job-collection) package that allows new jobs to be scheduled using the [Later.js text parser format](https://bunkat.github.io/later/parsers.html#text)  .

To run locally (assuming you have Meteor.js [installed](https://www.meteor.com/install)):

```bash
git clone https://github.com/vsivsi/meteor-job-collection-playground.git jcPlay
cd jcPlay
meteor npm install
meteor
# Now point your browser to http://localhost:3000
```

You can also find a hosted version of this app at [https://jcplayground.meteorapp.com](https://jcplayground.meteorapp.com)

If you are interested in plain node.js workers for job-collection, there is a sample worker implementation that will work on jobs hosted by the jcplayground server here: https://github.com/vsivsi/meteor-job-collection-playground-worker
