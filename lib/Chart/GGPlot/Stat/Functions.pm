package Chart::GGPlot::Stat::Functions;

use Chart::GGPlot::Setup qw(:base :pdl);

use Chart::GGPlot::Layer::Functions qw(layer);
use Chart::GGPlot::Types;
use Chart::GGPlot::Util qw(:all);

use parent qw(Exporter::Tiny);

my @export_ggplot = qw(
  stat_identity
);
our @EXPORT_OK = @export_ggplot;
our %EXPORT_TAGS = (
    all    => \@EXPORT_OK,
    ggplot => \@export_ggplot,
);

fun stat_identity(
    : $mapping     = undef,
    : $data        = undef,
    : $geom        = "point",
    : $position    = "identity",
    : $show_legend = NA(),
    : $inherit_aes = true, %rest
  )
{
    return layer(
        mapping     => $mapping,
        data        => $data,
        stat        => 'identify',
        position    => $position,
        show_legend => $show_legend,
        inherit_aes => $inherit_aes,
        geom        => 'blank',
        params      => { na_rm => false, %rest },
    );
}

fun geom_histogram(
    : $mapping     = undef,
    : $data        = undef,
    : $stat        = "bin",
    : $position    = "stack",
    : $binwidth    = undef,
    : $bins        = undef,
    : $na_rm       = false,
    : $show_legend = undef,
    : $inherit_aes = true,
    %rest
  )
{
    return layer(
        data        => $data,
        mapping     => $mapping,
        stat        => stat,
        geom        => 'bar',
        position    => $position,
        show_legend => $show_legend,
        inherit_aes => $inherit_aes,
        params      => {
            binwidth => $binwidth,
            bins     => $bins,
            na_rm    => $na_rm,
            pad      => false,
            %rest
        },
    );
}

1;