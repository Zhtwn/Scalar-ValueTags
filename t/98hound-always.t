use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
# DO NOT SKIP even if unavailable, to check the base API is harmless here

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

add_value_tag( $vt_type, \my $var, [] );
clear_value_tags( $vt_type, \$var );

is( get_value_tags( $vt_type, \$var ), undef,
    'variable should not have value tags' );

done_testing;
