use v5;
use strict;
use warnings;

use Module::Build;

my $with_trace;
@ARGV = grep { $_ eq "--with-trace" ? ( $with_trace++, 0 ) : 1 } @ARGV;

my $build = Module::Build->new(
   module_name => 'Scalar::ValueTags',
   configure_requires => {
      'Module::Build' => "0.4004", # test_requires
   },
   requires => {
      'perl' => '5.028',
   },
   test_requires => {
      'Feature::Compat::Try' => 0,
      'List::Util::PP' => 0,
      'Test2::V0' => 0,
   },
   extra_compiler_flags => [
       $with_trace ? ( "-DDEBUG_TRACE_ANNOTATIONS" ) : (),
   ],
   license => 'perl',
   create_license => 1,
   create_readme  => 1,
);

if( eval { require Devel::MAT::Dumper::Helper and
            Devel::MAT::Dumper::Helper->VERSION( '0.45' ) } ) {
   Devel::MAT::Dumper::Helper->extend_module_build( $build );
}

$build->create_build_script;
