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

list_value_tags_ok( sub ($x) { split m/,/, $x }, [qw( one two three )], "split" );

list_value_tags_ok( sub ($x) { ( "$x" =~ m/(.*),(.*),(.*)/ )[0,1,2] }, [qw( one two three )], "match OPf_STACKED+OPf_LIST" );
list_value_tags_ok( sub ($x) { ( $x =~ m/(.*),(.*),(.*)/ )[0,1,2] }, [qw( one two three )], "match OPf_LIST" );
list_value_tags_ok( sub ($x) { $x =~ m/(.*),(.*),(.*)/ }, [qw( one two three )], "match unknown context" );
list_value_tags_ok( sub ($x) { $_ = $x; m/(.*),(.*),(.*)/ }, [qw( one two three )], "match unknown context on defsv" );

# Tests of regexp -> dollardigit copy
list_value_tags_ok(
    sub ($x) { $x =~ m/(.*),(.*),(.*)/;( $1, $2, $3 ) }, [qw( one two three )],
    'basic match capture buffers' );
list_value_tags_ok(
    sub ($x) { $x =~ m/(.*),(.*),(.*)/; { "another" =~ m/(.*)/; } ( $1, $2, $3 ) }, [qw( one two three )],
    'match capture buffers are localised per block' );

{
    my $inp = "input string";
    add_value_tag( $vt_type, \$inp, my $dat = [] );

    $inp =~ m/(.*)/; my $dollar1 = $1;
    "another string" =~ m/(.*)/; $dollar1 = $1;

    is( get_value_tags( $vt_type, \$1 ), undef,
        'second match in block clears value tags of first' );
}

list_value_tags_ok( sub ($x) { $x =~ s/,/-/; $x }, ["one-two,three"], 'subst const' );
list_value_tags_ok( sub ($x) { $x =~ s/,/-/g; $x }, ["one-two-three"], 'subst const global' );
list_value_tags_ok( sub ($x) { $x =~ s/,//; $x }, ["onetwo,three"], 'subst const shorter' );
list_value_tags_ok( sub ($x) { $x =~ s/,/--/; $x }, ["one--two,three"], 'subst const longer' );
list_value_tags_ok( sub ($x) { $x =~ s/,/-/r }, ["one-two,three"], 'subst const non-destruct' );
list_value_tags_ok( sub ($x) { $x =~ s/,/-/gr }, ["one-two-three"], 'subst const global non-destruct' );
list_value_tags_ok( sub ($x) { $x =~ s/,//r }, ["onetwo,three"], 'subst const non-destruct longer' );
list_value_tags_ok( sub ($x) { $x =~ s/,/--/r }, ["one--two,three"], 'subst const non-destruct shorter' );
list_value_tags_ok( sub ($x) { $x =~ s/,...,/-two-/; $x }, ["one-two-three"], 'subst const variable-pattern' );
list_value_tags_ok( sub ($x) { $x =~ s/,...,/-two-/r }, ["one-two-three"], 'subst const variable-pattern non-destruct' );
list_value_tags_ok( sub ($x) { "$x" =~ s/,/-/gr }, ["one-two-three"], 'subst const global non-destruct OPf_STACKED' );
list_value_tags_ok( sub ($x) { $_ = $x; s/,/-/g; $_ }, ["one-two-three"], 'subst const global on defsv' );
list_value_tags_ok( sub ($x) { my $s = "four,five"; $s =~ s/.*/$x/; $s }, ["one,two,three"], 'subst expr[padsv]' );
list_value_tags_ok( sub ($x) { my $s = "four,five"; $s =~ s/.*/$x/r }, ["one,two,three"], 'subst expr[padsv] non-destruct' );
list_value_tags_ok( sub ($x) { $_ = "four,five"; s/.*/$x/; $_ }, ["one,two,three"], 'subst expr[padsv] on defsv' );
list_value_tags_ok( sub ($x) { $_ = "four,five"; s/.*/($x)/; $_ }, ["(one,two,three)"], 'subst expr[multiconcat] on defsv' );
list_value_tags_ok( sub ($x) { "four,five" =~ s/.*/($x)/r }, ["(one,two,three)"], 'subst expr[multiconcat] non-destruct' );
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
