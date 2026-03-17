#!/usr/bin/perl

use v5.14;
use warnings;
use feature 'signatures';

use Test2::V0;
use Test2::Tools::Subtest qw/ subtest_streamed /;

BEGIN {
    eval { require Devel::MAT; Devel::MAT->VERSION('0.49') }
      or plan skip_all =>
      "Devel::MAT version 0.49 required to test debug tracing";

    require Devel::MAT::Dumper;
}

use Data::Hounding;
skip_all "Data::Hounding is not available" unless IS_HOUNDING_ENABLED;
skip_all "Data::Hounding debug tracing is not enabled"
  unless IS_HOUNDING_TRACING_ENABLED;

my $orig_var = 123;
hound_apply( \$orig_var, my $datum = { data => "here" } );
my $derived_var = $orig_var;

( my $file = __FILE__ ) =~ s/\.t$/.pmat/;
Devel::MAT::Dumper::dump($file);
END { unlink $file if -f $file }

my $pmat = Devel::MAT->load($file);
my $df   = $pmat->dumpfile;

# Main vtbl root
my $vtbl_at = eval {
    $df->root_at("the Data::Hounding VTBL")
      || $df->root_at("the Data::Hounding Hook");
};
ok( defined $vtbl_at,
    'Dumpfile records address of Data::Hounding VTBL or Hook' );
my $trace_vtbl_at =
  eval { $df->root_at("the Data::Hounding debug trace VTBL") };
ok( defined $trace_vtbl_at,
    'Dumpfile records address of Data::Hounding debug trace VTBL' );

sub tracing_ok ( $var_sv, $expected, $varname ) {
    my @magics = $var_sv->magic;

    my ($hounding_magic) = grep { $_->vtbl == $vtbl_at } @magics;
    ok( defined $hounding_magic, "main_cv $varname has hounding magic" );

    ok( my $obj_sv = $hounding_magic->obj, 'hounding magic has obj' );
    is( $obj_sv->type,         "ARRAY", 'hounding magic obj is ARRAY' );
    is( scalar $obj_sv->elems, 1,       'hounding magic obj array has 1 elem' );

    my $annotation = $obj_sv->elem(0);
    ok( defined $annotation,
        'got first annotation from hounding magic obj array' );

    my @annotation_magics = $annotation->magic;
    is( scalar @annotation_magics, 1, 'annotation sv has some magic' );

    my ($trace_magic) = grep { $_->vtbl == $trace_vtbl_at } @annotation_magics;
    ok( defined $trace_magic, 'annotation sv has trace magic' );

    ok( my $trace_obj = $trace_magic->obj, "trace magic has obj" );
    is( $trace_obj->type, 'ARRAY', 'trace magic obj is ARRAY' );

    my $expected_count = scalar $expected->@*;
    my @elems          = $trace_obj->elems;
    is( scalar @elems,
        $expected_count,
        "trace magic obj should have $expected_count elements" );

    for my $i ( 0 .. $expected->$#* ) {
        my $expected_elem = $expected->[$i];
        my $elem          = $trace_obj->elem($i);

        is( $elem->type, 'SCALAR', "element $i type should be SCALAR" );

        my $op    = $expected_elem->{op};
        my $value = $expected_elem->{value};
        is( $elem->$op, $value, "element $i $op value should be $value" );
    }
}

my $main_cv = $df->main_cv;

ok( my $orig_var_sv = $main_cv->maybe_lexvar('$orig_var'),
    'main_cv has orig var' );

tracing_ok(
    $orig_var_sv,
    [
        { op => 'uv', value => 0 },
        { op => 'pv', value => 't/83devel-debug-trace.t:22' }
    ],
    '$orig_var'
);

ok( my $derived_var_sv = $main_cv->maybe_lexvar('$derived_var'),
    'main_cv has derived var' );

tracing_ok( $derived_var_sv, [ { op => 'uv', value => 1 }, ], '$derived_var' );

done_testing;
