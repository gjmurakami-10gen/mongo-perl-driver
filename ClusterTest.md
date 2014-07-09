# Mongo Shell Cluster Testing Notes

    cpan IO::String List::Flatten String::Util
    
## mongo shell test framework essentials

- based on mongo shell ReplSetTest and ShardingTest objects
- language interface communicates via socket to the mongo shell
- requests are JavaScript statements, responses are mixed text and JSON
- mongo-ruby-driver
    - runs 96 replica set tests in less than 3 minutes
    - runs 14 sharding tests in 1 minute
    - the replica set / sharded cluster is not shutdown after each test, instead nodes are restarted if necessary
    - mongo shell output is logged to mongo_shell.log, lines are prefixed by a process tag
    - dataPath is CWD/data/
    - classes Mongo::Shell, Mongo::ClusterTest::Node, Mongo::ReplSetTest, Mongo::ShardingTest
    - methods provided for nodes, primary, secondaries, uri, kill, stop
    - MONGO_SHUTDOWN=0 environment variable to NOT shutdown the cluster and mongo shell after running tests
      permitting subsequent tests to be run in less than a second instead of suffering 25-second replica set startup
      and examination of live cluster and database

## Status

## Work items

- initial mongo shell test and Moo class 

## Perl environment setup

    cpan App:perlbrew
    perlbrew init
    source ~/perl5/perlbrew/etc/bashrc
    echo source ~/perl5/perlbrew/etc/bashrc >> ~/.bashrc
    perlbrew install perl-5.20.0
    perlbrew switch perl-5.20.0
    which perl
    perl -v
    sudo chown -R gjm:staff /Users/gjm/.cpan
    cpan MongoDB
    
    perl Makefile.PL
    make
    make test
    
    cpan Devel::Cover
    cover --delete
    make cover
    cover
    browse cover_db/coverage.html
    