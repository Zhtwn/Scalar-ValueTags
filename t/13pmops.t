use v5.28;
use feature 'signatures';

use Test2::V0;
no warnings 'experimental::signatures';

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;

sub list_hounded_ok ( $code, $result, $name )
{
    my $inp = "one,two,three";
    hound_apply( \$inp, my $dat = { datum => "here" } );

    my @out = $code->( $inp );
    is( [ hound_query( \$out[$_] ) ], [ exact_ref($dat) ],
        "$name preserves hounding on output value [$_]" ) for keys @out;
    is( \@out, $result, "$name yields correct results" );

    my $second_inp = "one,two,three";
    hound_apply( \$second_inp, my $second_dat = { datum => "second" } );
    my @second_out = $code->( $second_inp );
    is( [ hound_query( \$second_out[$_] ) ], [ exact_ref($second_dat) ],
        "$name a second time does not leak on output value [$_]" ) for keys @second_out;
}

list_hounded_ok( sub ($x) { split m/,/, $x }, [qw( one two three )], "split" );

list_hounded_ok( sub ($x) { ( "$x" =~ m/(.*),(.*),(.*)/ )[0,1,2] }, [qw( one two three )], "match OPf_STACKED+OPf_LIST" );
list_hounded_ok( sub ($x) { ( $x =~ m/(.*),(.*),(.*)/ )[0,1,2] }, [qw( one two three )], "match OPf_LIST" );
list_hounded_ok( sub ($x) { $x =~ m/(.*),(.*),(.*)/ }, [qw( one two three )], "match unknown context" );
list_hounded_ok( sub ($x) { $_ = $x; m/(.*),(.*),(.*)/ }, [qw( one two three )], "match unknown context on defsv" );

# Tests of regexp -> dollardigit copy
list_hounded_ok(
    sub ($x) { $x =~ m/(.*),(.*),(.*)/;( $1, $2, $3 ) }, [qw( one two three )],
    'basic match capture buffers' );
list_hounded_ok(
    sub ($x) { $x =~ m/(.*),(.*),(.*)/; { "another" =~ m/(.*)/; } ( $1, $2, $3 ) }, [qw( one two three )],
    'match capture buffers are localised per block' );

{
    my $inp = "input string";
    hound_apply( \$inp, my $dat = [] );

    $inp =~ m/(.*)/; my $dollar1 = $1;
    "another string" =~ m/(.*)/; $dollar1 = $1;

    is( [ hound_query( \$1 ) ], [],
        'second match in block clears hounding of first' );
}

list_hounded_ok( sub ($x) { $x =~ s/,/-/; $x }, ["one-two,three"], 'subst const' );
list_hounded_ok( sub ($x) { $x =~ s/,/-/g; $x }, ["one-two-three"], 'subst const global' );
list_hounded_ok( sub ($x) { $x =~ s/,//; $x }, ["onetwo,three"], 'subst const shorter' );
list_hounded_ok( sub ($x) { $x =~ s/,/--/; $x }, ["one--two,three"], 'subst const longer' );
list_hounded_ok( sub ($x) { $x =~ s/,/-/r }, ["one-two,three"], 'subst const non-destruct' );
list_hounded_ok( sub ($x) { $x =~ s/,/-/gr }, ["one-two-three"], 'subst const global non-destruct' );
list_hounded_ok( sub ($x) { $x =~ s/,//r }, ["onetwo,three"], 'subst const non-destruct longer' );
list_hounded_ok( sub ($x) { $x =~ s/,/--/r }, ["one--two,three"], 'subst const non-destruct shorter' );
list_hounded_ok( sub ($x) { $x =~ s/,...,/-two-/; $x }, ["one-two-three"], 'subst const variable-pattern' );
list_hounded_ok( sub ($x) { $x =~ s/,...,/-two-/r }, ["one-two-three"], 'subst const variable-pattern non-destruct' );
list_hounded_ok( sub ($x) { "$x" =~ s/,/-/gr }, ["one-two-three"], 'subst const global non-destruct OPf_STACKED' );
list_hounded_ok( sub ($x) { $_ = $x; s/,/-/g; $_ }, ["one-two-three"], 'subst const global on defsv' );
list_hounded_ok( sub ($x) { my $s = "four,five"; $s =~ s/.*/$x/; $s }, ["one,two,three"], 'subst expr[padsv]' );
list_hounded_ok( sub ($x) { my $s = "four,five"; $s =~ s/.*/$x/r }, ["one,two,three"], 'subst expr[padsv] non-destruct' );
list_hounded_ok( sub ($x) { $_ = "four,five"; s/.*/$x/; $_ }, ["one,two,three"], 'subst expr[padsv] on defsv' );
list_hounded_ok( sub ($x) { $_ = "four,five"; s/.*/($x)/; $_ }, ["(one,two,three)"], 'subst expr[multiconcat] on defsv' );
list_hounded_ok( sub ($x) { "four,five" =~ s/.*/($x)/r }, ["(one,two,three)"], 'subst expr[multiconcat] non-destruct' );
# TODO: There may be other combinations as yet untested that have subtle weird
# behaviours

# subst with a constant should -not- obtain hounding if it fails to match
{
    my $repl = "repl"; hound_apply( \$repl, [ "ignore-me" ] );

    my $x = "abcd"; $x =~ s/xyz/$repl/;
    is( [ hound_query( \$x ) ], [],
        'var remains unhounded after unsuccessful subst' );

    my $y = "abcd" =~ s/xyz/$repl/r;
    is( [ hound_query( \$x ) ], [],
        'result remains unhounded after unsuccessful subst non-destruct' );
}

done_testing;
