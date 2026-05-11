use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

sub list_value_tags_ok ( $code, $result, $name )
{
    my $inp = "one,two,three";
    add_value_tag( $vt_type, \$inp, my $dat = { datum => "here" } );

    my @out = $code->( $inp );
    is( get_value_tags( $vt_type, \$out[$_] ), [ exact_ref($dat) ],
        "$name preserves value tags on output value [$_]" ) for keys @out;
    is( \@out, $result, "$name yields correct results" );

    my $second_inp = "one,two,three";
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );
    my @second_out = $code->( $second_inp );
    is( get_value_tags( $vt_type, \$second_out[$_] ), [ exact_ref($second_dat) ],
        "$name a second time does not leak on output value [$_]" ) for keys @second_out;
}

# TODO: There may be other combinations as yet untested that have subtle weird
# behaviours

# subst with a constant should -not- obtain value tags if it fails to match
{
    my $repl = "repl"; add_value_tag( $vt_type, \$repl, [ "ignore-me" ] );

    my $x = "abcd"; $x =~ s/xyz/$repl/;
    is( get_value_tags( $vt_type, \$x ), undef,
        'var remains untagged after unsuccessful subst' );

    my $y = "abcd" =~ s/xyz/$repl/r;
    is( get_value_tags( $vt_type, \$x ), undef,
        'result remains untagged after unsuccessful subst non-destruct' );
}

done_testing;
