# This script is run in the discourse_test docker image to prepopulate the database
# Available environment variables:
# => NO_UPDATE        disables updating the source code within the discourse_test docker image
# => COMMIT_HASH      used by the discourse_test docker image to load a specific commit of discourse
#                     this can also be set to a branch, e.g. "origin/tests-passed"

puts "travis_fold:end:starting_docker_container" if ENV["TRAVIS"]

def run_or_fail(command)
  pid = Process.spawn(command)
  Process.wait(pid)
  exit 1 unless $?.exitstatus == 0
end

#  if ENV['PARALLEL_TESTS']
@parallel_count = ENV["PARALLEL_COUNT"] || 3

puts "travis_fold:start:prepare_tests" if ENV["TRAVIS"]
puts "Cleaning up old test tmp data in tmp/test_data"
`rm -fr tmp/test_data && mkdir -p tmp/test_data/redis && mkdir tmp/test_data/pg`

puts "Starting background redis"
@redis_pid = Process.spawn('redis-server --dir tmp/test_data/redis')

@postgres_bin = "/usr/lib/postgresql/10/bin/"
`#{@postgres_bin}initdb -D tmp/test_data/pg`

# speed up db, never do this in production mmmmk
`echo fsync = off >> tmp/test_data/pg/postgresql.conf`
`echo full_page_writes = off >> tmp/test_data/pg/postgresql.conf`
`echo shared_buffers = 500MB >> tmp/test_data/pg/postgresql.conf`

puts "Starting postgres"
@pg_pid = Process.spawn("#{@postgres_bin}postmaster -D tmp/test_data/pg")

ENV["RAILS_ENV"] = "test"

@good &&= run_or_fail("bundle exec rake parallel:create[#{@parallel_count}]")
@good &&= run_or_fail("bundle exec rake parallel:migrate[#{@parallel_count}]")
puts "bundle exec rake parallel:spec STARTED with #{@parallel_count} parallel tests"
@good &&= run_or_fail("bundle exec rake parallel:spec[#{@parallel_count}]")
puts "bundle exec rake parallel:spec ENDED"
#  end
