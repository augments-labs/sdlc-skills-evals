// Runs scheduled jobs in-process. Nothing is persisted: a job that is
// running when the worker restarts is lost, and one that fell due while the
// worker was down never runs.
const jobs = [];

function schedule(name, everyMs, handler) {
  const job = { name, everyMs, handler };
  job.timer = setInterval(() => run(job), everyMs);
  jobs.push(job);
  return job;
}

function run(job) {
  return job.handler();
}

module.exports = { schedule, run, jobs };
