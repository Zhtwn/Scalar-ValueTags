use v5.28;
use feature 'signatures';

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
}

package StringifiesAsElem0 {
    use overload '""' => sub { return (shift)->[0] };
}

value_tags_ok(
    sub ( $x ) {
        my $obj = bless [$x], "StringifiesAsElem0";
        return "$obj";
    }, "1",
    'stringification overloading' );

package NumifiesAsElem0 {
    use overload '0+' => sub { return (shift)->[0] };
}

value_tags_ok(
    sub ( $x ) {
        my $obj = bless [$x], "NumifiesAsElem0";
        return int($obj);  # int() invokes numify overload
    }, 1,
    'numification overloading' );

done_testing;
