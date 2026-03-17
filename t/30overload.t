use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

sub hounded_ok ( $code, $result, $name )
{
    my $inp = "1";
    hound_apply( \$inp, my $dat = { datum => "here" } );

    my $out = $code->( $inp );
    is( [ hound_query( \$out ) ], [ exact_ref($dat) ],
        "$name preserves hounding on output" );
    is( $out, $result, "$name yields correct result" );
}

package StringifiesAsElem0 {
    use overload '""' => sub { return (shift)->[0] };
}

hounded_ok(
    sub ( $x ) {
        my $obj = bless [$x], "StringifiesAsElem0";
        return "$obj";
    }, "1",
    'stringification overloading' );

package NumifiesAsElem0 {
    use overload '0+' => sub { return (shift)->[0] };
}

hounded_ok(
    sub ( $x ) {
        my $obj = bless [$x], "NumifiesAsElem0";
        return int($obj);  # int() invokes numify overload
    }, 1,
    'numification overloading' );

done_testing;
