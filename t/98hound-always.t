use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
# DO NOT SKIP even if unavailable, to check the base API is harmless here

hound_apply( \my $var, [] );
hound_delete( \$var );

is( [ hound_query( \$var ) ], [],
    'hound_query yields empty list' );

done_testing;
