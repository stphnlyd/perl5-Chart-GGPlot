#!/usr/bin/env perl

use 5.016;
use warnings;

use Getopt::Long;
use Chart::GGPlot::Functions qw(:all);
use Data::Frame::More::Examples qw(diamonds);

my $save_as;
GetOptions( 'o=s' => \$save_as );

my $dsamp = diamonds()->sample(1000);

my $p = ggplot(
    data    => $dsamp,
    mapping => aes( x => 'carat', y => 'price' )
)->geom_point( mapping => aes( color => 'clarity' ) )
 ->scale_color_hue( h => [270, 360] );

if (defined $save_as) {
    $p->save($save_as);
} else {
    $p->show();
}
