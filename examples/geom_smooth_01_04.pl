#!/usr/bin/env perl

# Disable confidence interval

use 5.016;
use warnings;

use Getopt::Long;
use Chart::GGPlot qw(:all);
use Data::Frame::Examples qw(mpg);

my $save_as;
GetOptions( 'o=s' => \$save_as );

my $mpg = mpg();

my $p = ggplot(
    data    => $mpg,
    mapping => aes( x => 'displ', y => 'hwy' )
)->geom_point()->geom_smooth(method => 'glm', se => 0);

if (defined $save_as) {
    $p->save($save_as);
} else {
    $p->show();
}

