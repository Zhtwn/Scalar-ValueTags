use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

sub listop_hounded_ok ( $argspec, $code, $result, $name )
{
    my @args; my @checks;
    my $idx;
    foreach ( split //, $argspec ) {
        my $inp = "xyz";
        my $hdatum = { datum => "here" . $idx++ };
        hound_apply( \$inp, $hdatum );
        push @args, $inp;
        push @checks, exact_ref($hdatum) if m/H/;
    }

    my $out = $code->( @args );
    is( [ hound_query( \$out ) ],
        bag { item $_ for @checks; end() }, # account for it possibly not being in order
        "$name preserves hounding on output" );
    is( $out, $result, "$name yields correct result" );

    # To check for leakage, we just need to over-specify. Run it once with
    # every input hounded with one datum, then check that annotation does not
    # appear in the result
    my $first_inp = "xyz";
    hound_apply( \$first_inp, my $first_dat = { datum => "first" } );
    my $first_out = $code->( ( $first_inp ) x length $argspec );

    my $second_inp = "xyz";
    hound_apply( \$second_inp, my $second_dat = { datum => "second" } );
    my $second_out = $code->( ( $second_inp ) x length $argspec );
    is( [ hound_query( \$second_out ) ],
        [ exact_ref($second_dat) ],
        "$name a second time does not leak" );
}

listop_hounded_ok( "HHH", sub ($sep, @s) { join $sep, @s }, "xyzxyzxyz", "join" );

# OP_MULTICONCAT has many forms
listop_hounded_ok( "HH", sub ($x, $y) { "paste ($x) and ($y)" }, "paste (xyz) and (xyz)",
    "multiconcat (padtmp)" );
listop_hounded_ok( "HH", sub ($x, $y) { my $ret = "paste ($x) and ($y)"; $ret }, "paste (xyz) and (xyz)",
    "multiconcat (my \$lex)" );
listop_hounded_ok( "HH", sub ($x, $y) { my $ret; $ret = "paste ($x) and ($y)"; $ret }, "paste (xyz) and (xyz)",
    "multiconcat (\$lex)" );
listop_hounded_ok( "HH", sub ($x, $y) { my @ret; $ret[0] = "paste ($x) and ($y)"; $ret[0] }, "paste (xyz) and (xyz)",
    "multiconcat (\$lex)" );
listop_hounded_ok( "HHH", sub ($pre, $x, $y) { my $ret = $pre; $ret .= " and ($x) and ($y)"; $ret }, "xyz and (xyz) and (xyz)",
    "multiconcat (\$lex append)" );

# Perl will turn a simple sprintf with just %s into an OP_MULTICONCAT so we
# have to be more subtle here
listop_hounded_ok( "HH", sub ($x, $y) { sprintf "format with %3s and %3s", $x, $y }, "format with xyz and xyz",
    "sprintf" );

# OP_STRINGIFY is a listop despite only taking 1 argument
listop_hounded_ok( "H", sub ($x) { "$x" }, "xyz", "stringify" );

listop_hounded_ok( "H", sub ($x) { return substr $x, 1, 1 }, "y", "substr (3arg non-MOD)" );
listop_hounded_ok( "H", sub ($x) { return substr $x, 1, 1, "B" }, "y", "substr (4arg non-MOD)" );
listop_hounded_ok( "H", sub ($x) { my $ret = "ABC"; substr $ret, 1, 1, $x; $ret; }, "AxyzC", "substr (4arg non-MOD) mutation" );
listop_hounded_ok( "H", sub ($x) { my $ret = "ABC"; substr( $ret, 1, 1 ) = $x; $ret; }, "AxyzC", "substr (3arg MOD rewritten)" );
# Perl will rewrite a simple  substr($x, $n, $c) = $y  into a 4-arg with
# reördered arguments, so we have to test true lvalue returns via $_
listop_hounded_ok( "H", sub ($x) { my $ret = "ABC"; $_ = $x for substr( $ret, 1, 1 ); $ret; }, "AxyzC", "substr (3arg MOD)" );

done_testing;
