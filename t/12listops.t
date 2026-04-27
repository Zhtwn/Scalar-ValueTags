use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Scalar::ValueTags;
skip_all "Scalar::ValueTags is not available" unless value_tags_enabled;

# use same Scalar::ValueTags type for all tests
my $vt_type = register_value_tags_type(SVTAGS_UNIQUE_REF_ARRAY);

sub listop_value_tags_ok ( $argspec, $code, $result, $name )
{
    my @args; my @checks;
    my $idx;
    foreach ( split //, $argspec ) {
        my $inp = "xyz";
        my $hdatum = { datum => "here" . $idx++ };
        add_value_tag( $vt_type, \$inp, $hdatum );
        push @args, $inp;
        push @checks, exact_ref($hdatum) if m/H/;
    }

    my $out = $code->( @args );
    is( get_value_tags( $vt_type, \$out ),
        bag { item $_ for @checks; end() }, # account for it possibly not being in order
        "$name preserves value tags on output" );
    is( $out, $result, "$name yields correct result" );

    # To check for leakage, we just need to over-specify. Run it once with
    # every input having one value tag, then check that annotation does not
    # appear in the result
    my $first_inp = "xyz";
    add_value_tag( $vt_type, \$first_inp, my $first_dat = { datum => "first" } );
    my $first_out = $code->( ( $first_inp ) x length $argspec );

    my $second_inp = "xyz";
    add_value_tag( $vt_type, \$second_inp, my $second_dat = { datum => "second" } );
    my $second_out = $code->( ( $second_inp ) x length $argspec );
    is( get_value_tags( $vt_type, \$second_out ),
        [ exact_ref($second_dat) ],
        "$name a second time does not leak" );
}

listop_value_tags_ok( "HHH", sub ($sep, @s) { join $sep, @s }, "xyzxyzxyz", "join" );

# OP_MULTICONCAT has many forms
listop_value_tags_ok( "HH", sub ($x, $y) { "paste ($x) and ($y)" }, "paste (xyz) and (xyz)",
    "multiconcat (padtmp)" );
listop_value_tags_ok( "HH", sub ($x, $y) { my $ret = "paste ($x) and ($y)"; $ret }, "paste (xyz) and (xyz)",
    "multiconcat (my \$lex)" );
listop_value_tags_ok( "HH", sub ($x, $y) { my $ret; $ret = "paste ($x) and ($y)"; $ret }, "paste (xyz) and (xyz)",
    "multiconcat (\$lex)" );
listop_value_tags_ok( "HH", sub ($x, $y) { my @ret; $ret[0] = "paste ($x) and ($y)"; $ret[0] }, "paste (xyz) and (xyz)",
    "multiconcat (\$lex)" );
listop_value_tags_ok( "HHH", sub ($pre, $x, $y) { my $ret = $pre; $ret .= " and ($x) and ($y)"; $ret }, "xyz and (xyz) and (xyz)",
    "multiconcat (\$lex append)" );

# Perl will turn a simple sprintf with just %s into an OP_MULTICONCAT so we
# have to be more subtle here
listop_value_tags_ok( "HH", sub ($x, $y) { sprintf "format with %3s and %3s", $x, $y }, "format with xyz and xyz",
    "sprintf" );

# OP_STRINGIFY is a listop despite only taking 1 argument
listop_value_tags_ok( "H", sub ($x) { "$x" }, "xyz", "stringify" );

listop_value_tags_ok( "H", sub ($x) { return substr $x, 1, 1 }, "y", "substr (3arg non-MOD)" );
listop_value_tags_ok( "H", sub ($x) { return substr $x, 1, 1, "B" }, "y", "substr (4arg non-MOD)" );
listop_value_tags_ok( "H", sub ($x) { my $ret = "ABC"; substr $ret, 1, 1, $x; $ret; }, "AxyzC", "substr (4arg non-MOD) mutation" );
listop_value_tags_ok( "H", sub ($x) { my $ret = "ABC"; substr( $ret, 1, 1 ) = $x; $ret; }, "AxyzC", "substr (3arg MOD rewritten)" );
# Perl will rewrite a simple  substr($x, $n, $c) = $y  into a 4-arg with
# reördered arguments, so we have to test true lvalue returns via $_
listop_value_tags_ok( "H", sub ($x) { my $ret = "ABC"; $_ = $x for substr( $ret, 1, 1 ); $ret; }, "AxyzC", "substr (3arg MOD)" );

done_testing;
