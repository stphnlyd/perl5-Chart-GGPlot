package Chart::GGPlot::Functions;

# ABSTRACT: Function interface of Chart::GGPlot

use Chart::GGPlot::Setup qw(:base :pdl);

# VERSION

use Data::Munge qw(elem);
use Data::Frame::More::Types qw(DataFrame);
use Data::Frame::More::Util qw(guess_and_convert_to_pdl);
use Module::Load;
use Types::Standard qw(Maybe Str);

use Chart::GGPlot;
use Chart::GGPlot::Aes;
use Chart::GGPlot::Util qw(factor);

use parent qw(Exporter::Tiny);

our @EXPORT_OK = qw(ggplot qplot);

for my $package (qw(Chart::GGPlot::Aes::Functions)) {
    load $package, ':ggplot';
    no strict 'refs';
    push @EXPORT_OK, @{ ${"${package}::EXPORT_TAGS"}{ggplot} };
    push @EXPORT_OK, qw(factor);
}

our %EXPORT_TAGS = ( all => \@EXPORT_OK );

=func ggplot

    my $ggplot = ggplot(:$data, :$mapping, %rest)

=cut

sub ggplot {
    return Chart::GGPlot->new(@_);
}

fun qplot (
    :$x, :$y, 
    :$facets = undef,
    Str :$geom = "auto",
    :$xlim = undef, :$ylim = undef,
    :$title = undef, :$xlab = 'x', :$ylab = 'y',
#    : $log     = "",
#    : $asp     = undef,
    %rest
  ) {

    my $all_aesthetics = Chart::GGPlot::Aes->all_aesthetics;

    $x = guess_and_convert_to_pdl($x);
    $y = guess_and_convert_to_pdl($y);

    unless ( $x->length == $y->length ) {
        die "x and y must have same length";
    }

    my $mapping = aes( x => 'x', y => 'y' );
    for my $aes ( grep { elem( $_, $all_aesthetics ) } keys %rest ) {
        $mapping->set( $aes, $aes );
    }

    $log->debug('qplot() $mapping = ' . Dumper($mapping));

    my $data = Data::Frame::More->new(
        columns => [
            x => guess_and_convert_to_pdl($x),
            y => guess_and_convert_to_pdl($y),

            $mapping->keys->grep( sub { $_ ne 'x' and $_ ne 'y' } )->map(
                sub {
                    my $d = guess_and_convert_to_pdl( $rest{$_} );
                    $_ => $d->repeat_to_length( $x->length );
                }
            )->flatten
        ]
    );

    my $p = ggplot( data => $data, mapping => $mapping );

    if ( not defined $facets ) {
        $p->facet_null();
    }
    else {
        die "'facets' is not yet supported.";
    }

    $p->ggtitle($title) if ( defined $title );
    $p->xlab($xlab)     if ( defined $xlab );
    $p->ylab($ylab)     if ( defined $ylab );

    my $geom_func;
    if ( $geom eq 'auto' ) {
        $geom_func = 'geom_point';
    }
    else {
        $geom_func = "geom_${geom}";
    }

    $p->$geom_func();

    #    my $logv = fun($var) { index( $log, $var ) >= 0 };
    #
    #    if ( $logv->('x') ) { $p = $p + scale_x_log10(); }
    #    if ( $logv->('y') ) { $p = $p + scale_y_log10(); }
    #
    #    if ( defined $asp ) { $p = $p + theme( aspect_ratio = $asp ); }
    #    if ( defined $xlab ) { $p = $p + xlim($xlab); }
    #    if ( defined $ylab ) { $p = $p + ylim($ylab); }
    #    if ( defined $xlim ) { $p = $p + xlim($xlim); }
    #    if ( defined $ylim ) { $p = $p + ylim($ylim); }

    return $p;
}

1;

__END__

=head1 SEE ALSO

L<Chart::GGPlot>