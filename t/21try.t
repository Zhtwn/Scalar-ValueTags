use v5.28;
use feature 'signatures';
use Feature::Compat::Try;

use Test2::V0;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

sub value_tags_ok ( $code, $result, $name )
{
    my $inp = "1";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( get_value_tags( $vt_type, \$out ), [ exact_ref($dat) ],
        "$name preserves value tags on output" );
    is( $out, $result, "$name yields correct result" );

    my $second_inp = "1";
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );
    my $second_out = $code->( $second_inp );
    is( get_value_tags( $vt_type, \$second_out ), [ exact_ref($second_dat) ],
        "$name a second time does not leak on output" );
}

value_tags_ok( sub ($x) {
    my $e = eval { die "Value is $x\n"; 1 } ? undef : $@;
    return $e;
}, "Value is 1\n", 'eval{} + $@' );

value_tags_ok( sub ($x) {
    try { die "Value is $x\n"; }
    catch($e) { return $e };
    return undef;
}, "Value is 1\n", 'try/catch' );

done_testing;
