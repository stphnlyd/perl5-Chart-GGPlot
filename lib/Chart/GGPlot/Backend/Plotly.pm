package Chart::GGPlot::Backend::Plotly;

# ABSTRACT: Plotly backend for Chart::GGPlot

use Chart::GGPlot::Class qw(:pdl);
use namespace::autoclean;

# VERSION

with qw(Chart::GGPlot::Backend);

use Chart::Plotly 0.023 qw(show_plot);
use Chart::Plotly::Plot;
use Chart::Plotly::Image::Orca;

use Data::Munge qw(elem);
use JSON;
use List::AllUtils qw(pairmap pairwise);
use Module::Load;
use Types::Standard qw(HashRef Int);

use Chart::GGPlot::Aes;
use Chart::GGPlot::Util qw(:all);
use Chart::GGPlot::Backend::Plotly::Geom;
use Chart::GGPlot::Backend::Plotly::Util qw(br to_rgb);

#TODO: To test and see which value is proper.
our $WEBGL_THRESHOLD = 2000;

# Does not do any yet.
classmethod _split_on($data) {
    return [];
}

method layer_to_traces ($layer, $data, $layout, $plot) {
    return if ( $data->isempty );

    my $geom            = $layer->geom;
    my $class_geom      = ( ref($geom) || $geom );
    my $short           = $class_geom =~ s/^Chart::GGPlot::Geom:://r;
    my $class_geom_impl = "Chart::GGPlot::Backend::Plotly::Geom::$short";

    my $geom_params = $layer->geom_params;
    my $stat_params = $layer->stat_params;
    my $aes_params  = $layer->aes_params;
    my $param = $geom_params->merge($stat_params)->merge($aes_params);

    my $coord  = $layout->coord;

    my %discrete_scales = map {
        my $scale = $_;
        if ( $scale->isa('Chart::GGPlot::Scale::Discrete') ) {
            map { $_ => $scale } @{ $scale->aesthetics };
        }
        else {
            ();
        }
    } @{ $plot->scales->non_position_scales->scales };

    # variables that produce multiple traces and deserve their own legend entries
    my @split_legend = map { "${_}_raw" } ( sort keys %discrete_scales );
    $log->debugf( "Variables that would cause legend be splitted : %s",
        Dumper( \@split_legend ) )
      if $log->is_debug;

    my $split_by = [ @split_legend, @{$self->_split_on($data)} ];
    my $split_vars = $split_by->intersect($data->names);

    my $hover_text_aes;     # which aes shall be displayed in hover text?
    {
        # While $plot->labels also looks like containing what we need,
        # actually it be cleared or set to other values, so it can't
        # really be used for generating the hovertext. Here we would
        # get the aes from $layer->mapping and $layer->stat.
        my $map      = $layer->mapping;
        my $calc_aes = $layer->stat->default_aes->hslice(
            $layer->calculated_aes( $layer->stat->default_aes ) );
        $map = $map->merge($calc_aes);
        if ( $layer->inherit_aes ) {
            $map = $map->merge( $plot->mapping );
        }
        $hover_text_aes = Chart::GGPlot->make_labels($map);
    }

    # put x and y at first in plotly hover text
    my $all_aesthetics = Chart::GGPlot::Aes->all_aesthetics;
    my @hover_aes_ordered = (
        qw(x y),
        (
            sort grep {
                $_ ne 'x' and $_ ne 'y' and elem( $_, $all_aesthetics )
            } @{$hover_text_aes->keys}
        )
    );

    my $panel_to_traces = fun( $d, $panel_params ) {

        my %seen_hover_aes;
        my @hover_data = map {
            my $var = $hover_text_aes->at($_);
            if ($seen_hover_aes{$var}++) {
                ();
            } else {
                if ( $var->$_DOES('Eval::Quosure') ) {
                    $var = $var->expr;
                }
                my $col =
                    $d->exists("${_}_raw") ? $d->at("${_}_raw")
                  : $d->exists($_)         ? $d->at($_)
                  :                          undef;
                defined $col ? ( $var => $col->as_pdlsv ) : ();
            }
        } @hover_aes_ordered;
        my $hover_text = [ 0 .. $d->nrow - 1 ]->map(
            sub { join( br(), pairmap { "$a: " . $b->at($_) } @hover_data ); }
        );

        $d->set( 'hovertext', PDL::SV->new($hover_text) );

        #my $na_rm = $params->at('na_rm') // false;

        my @splitted_sorted;
        if ( $split_vars->length ) {
            my $fac = do {
                my $d_tmp      = $d->select_columns($split_vars);
                my $lvls       = $d_tmp->uniq->sort($split_vars);
                my $fac_levels = $lvls->id;
                my $i          = 0;
                my %fac_levels = map { $_ => $i++ } $fac_levels->flatten;
                my $fac_integers =
                  [ map { $fac_levels{$_} } $d_tmp->id->flatten ];
                PDL::Factor->new(
                    integer => $fac_integers,
                    levels  => [ 0 .. $fac_levels->length - 1 ],
                );
            };

            my $splitted = $d->split($fac);
            @splitted_sorted =
              map { $splitted->{$_} } sort { $a cmp $b } keys %$splitted;
        }
        else {
            push @splitted_sorted, $d;
        }

        return @splitted_sorted->map(
            sub {
                my ($d) = @_;

                my $trace = $class_geom_impl->to_trace($d);

                # If we need a legend, set legend info.
                my $show_legend =
                  @split_legend->intersect( $data->names )->length;
                if ($show_legend) {
                    my $legend_key = join(
                        ', ',
                        map {
                            if ( $d->exists($_) ) {
                                my $col_data = $d->at($_);
                                $col_data->slice(pdl(0))->as_pdlsv->at(0);
                            }
                            else {
                                ();
                            }
                        } @split_legend
                    );
                    $trace->{showlegend} = JSON::true;
                    $trace->{name}       = $legend_key;
                }
                return $trace;
            } 
        );
    };

    my $splitted = $data->split( $data->at('PANEL') );
    return [
        pairmap {
            my ( $panel_idx, $data ) = ( $a, $b );

            my $panel_params = $layout->panel_params->at($panel_idx);
            $panel_to_traces->( $data, $panel_params );
        }
        %$splitted
    ];
}

=method to_plotly

Returns a Chart::GPlotly object.

=cut

method to_plotly ($plot_built) {
    my $plot   = $plot_built->plot;
    my $layers = $plot->layers;
    my $layout = $plot_built->layout;

    my $plotly = Chart::Plotly::Plot->new();

    my $scales       = $layout->get_scales(0);
    my $panel_params = $layout->panel_params->at(0);

    # prepare theme and calc elements
    my $theme  = $plot->theme;
    my $elements = $theme->keys;
    for my $elname (@$elements) {
        my $el = $theme->at($elname);
        if ($el->$_DOES('Chart::GGPlot::Theme::Element')) {
            $theme->set($elname, $theme->calc_element($elname));
        }
    }

    my $el_panel_bg = $theme->at('panel_background');
    my $el_plot_bg  = $theme->at('plot_background');

    my %plotly_layout = (
        (
              ( not defined $el_panel_bg or $el_panel_bg->is_blank ) ? ()
            : ( plot_bgcolor => to_rgb( $el_panel_bg->at('fill') ) )
        ),
        (
              ( not defined $el_plot_bg or $el_plot_bg->is_blank ) ? ()
            : ( paper_bgcolor => to_rgb( $el_plot_bg->at('fill') ) )
        ),
    );

    my $labels        = $plot->labels;
    my $title = $labels->{title};
    if ( defined $labels->{title} and length($title) ) {

        # NOTE: plotly does not directly support subtitle
        #  See https://github.com/plotly/plotly.js/issues/233

        my $subtitle = $labels->{subtitle};
        if ( defined $subtitle and length($subtitle) ) {
            $title .= br() . sprintf( "%s", $subtitle );
        }
        $plotly_layout{title} = $title;
    }

    my $barmode;
    for my $xy (qw(x y)) {

        my $theme_el = sub {
            my ($elname) = @_;
            return ($theme->at("${elname}.${xy}") // $theme->at($elname));
        };

        my $sc =
            $plot->coordinates->DOES('Chart::GGPlot::Coord::Flip')
          ? $scales->{ $xy eq 'x' ? 'y' : 'x' }
          : $scales->{$xy};

        my $axis_title = $sc->name // $labels->at($xy) // '';

        my $range = $panel_params->{"$xy.range"}->unpdl;
        my $labels = $panel_params->{"$xy.labels"}->as_pdlsv->unpdl;
        my $major_source = $panel_params->{"$xy.major_source"}->unpdl;
        my %ticks = pairwise { $a => $b } @$major_source, @$labels;

        # TODO:
        # Plotly does not well support minor ticks. Although we could
        # specify empty string at ticktext for minor ticks (like via below
        # lines I comment out), because of plotly's limitation minor
        # and major ticks has to be of same tick length on axises, which
        # looks ugly. In contrast ggplot2 would defaultly have a zero 
        # length for minor ticks. R's plotly module simply discards minor
        # ticks. For now we just follow that.

        # There is not necessarily minor ticks for an axis.
        #my $minor_source = $panel_params->{"$xy.minor_source"};
        #my $tickvals =
        #  defined $minor_source ? $minor_source->unpdl : $major_source;

        my $tickvals = $major_source;
        my $ticktext = [ map { $ticks{$_} // '' } @$tickvals ];

        my ( $el_axis_line, $el_axis_text, $el_axis_ticks, $el_axis_title ) =
          map { $theme_el->($_) } qw(axis_line axis_text axis_ticks axis_title);
        my $el_panel_grid = $theme_el->('panel_grid_major')
          // $theme->at('panel_grid');

        $plotly_layout{"${xy}axis"} = {
            range     => $range,
            zeroline  => JSON::false,
            autorange => JSON::false,

            (
                  ( not defined $el_axis_title or $el_axis_title->is_blank )
                ? ()
                : ( title => $axis_title, )
            ),
            (
                  ( not defined $el_axis_ticks or $el_axis_ticks->is_blank )
                ? ()
                : (
                    ticks     => 'outside',
                    ticktext  => $ticktext,
                    tickvals  => $tickvals,
                    tickcolor => to_rgb( $el_axis_ticks->at('color') ),
                    tickangle => -( $el_axis_ticks->at('angle') // 0 ),
                )
            ),

            #ticklen => $theme->axis_ticks_length;
            #tickwidth => $el_axis_ticks,
            (
                  ( not defined $el_axis_text or $el_axis_text->is_blank )
                ? ( showticklabels => JSON::false, )
                : ( showticklabels => JSON::true, )
            ),
            (
                ( not defined $el_axis_line or $el_axis_line->is_blank ) ? ()
                : (
                    linecolor => to_rgb( $el_axis_line->at('color') ),
                    linewidth => 1,
                )
            ),
            (
                (
                    not defined $el_panel_grid
                      or $el_panel_grid->is_blank
                ) ? ( showgrid => JSON::false, )
                : (
                    gridcolor => to_rgb( $el_panel_grid->at('color') ),
                    gridwidth => to_rgb( $el_panel_grid->at('size') ),
                )
            ),
        };

        if ( $sc->isa('Chart::GGPlot::Scale::DiscretePosition') ) {
            my $has_dodge = List::AllUtils::any {
                $_->isa('Chart::GGPlot::Position::Dodge')
            } $layers->map( sub { $_->position } )->flatten;
            if ($has_dodge) {
                $barmode = 'dodge';
            }
        }
    } # for (qw(x y))

    for my $i ( 0 .. $#$layers ) {
        my $layer = $layers->[$i];
        my $data  = $plot_built->data->[$i];

        $log->debug( "data at layer $i:\n" . $data->string ) if $log->is_debug;

        my $panels_traces =
          $self->layer_to_traces( $layer, $data, $layout, $plot );
        for my $panel (@$panels_traces) {
            for my $trace (@$panel) {
                $plotly->add_trace($trace);
            }

            if ( List::AllUtils::any { $_->showlegend } @$panel ) {
                $plotly_layout{showlegend} = JSON::true;

                # legend title
                #
                # TODO: See if plotly will officially support legend title
                #  https://github.com/plotly/plotly.js/issues/276
                my $legend_titles =
                  join( "\n", map { $_->title } @{ $plot->guides->guides } );

                my $annotations = $plotly_layout{annotations} //= [];
                push @$annotations,
                  {
                    x         => 1.02,
                    y         => 1,
                    xanchor   => 'left',
                    yanchor   => 'bottom',
                    text      => $legend_titles,
                    showarrow => JSON::false,
                    xref      => 'paper',
                    yref      => 'paper',
                  };

                # Default right margin is too small for legend title.
                #
                # TODO: How to automatically calc the margin?
                #  May need to use libraries like Cairo for text width?
                #  Best if plotly can natively support legend title.
                $plotly_layout{margin} = { r => 150 };
            }
        }
    }

    $plotly_layout{hovermode} = 'closest';
    $plotly_layout{barmode} = $barmode // 'relative';
    
    # border
    my $el_panel_border = $theme->at('panel_border');
    unless ( not defined $el_panel_border or $el_panel_border->is_blank ) {
        $plotly_layout{shapes} = [
            {
                type      => 'rect',
                fillcolor => 'transparent',
                line      => {
                    color    => to_rgb( $el_panel_border->at('color') ),
                    width    => 1,
                    linetype => 'solid',
                },
                xref => 'paper',
                x0   => 0,
                x1   => 1,
                yref => 'paper',
                y0   => 0,
                y1   => 1,
            }
        ];
    }

    $log->debug( "plotly layout : " . Dumper( \%plotly_layout ) )
      if $log->is_debug;

    $plotly->layout( \%plotly_layout );

    #$log->trace( "plotly html:\n" . $plotly->html ) if $log->is_trace;

    return $plotly;
}

=method show
    
    $backend->show($ggplot, HashRef $opts={});

Show the plot like in web browser.

=method save

    $backend->save($ggplot, $filename, HashRef $opts={});

Export the plot to a static image file.

Below options are supported for C<$opts>:

=for :list
* width
* height

=cut

method ggplotly ($ggplot) {
    my $plot_built = $self->build($ggplot);
    return $self->to_plotly($plot_built);
}

method show ($ggplot, HashRef $opts={}) {
    my $plotly = $self->ggplotly($ggplot);
    show_plot( $plotly );
}

method save ($ggplot, $filename, HashRef $opts={}) {
    my $plotly = $self->ggplotly($ggplot);
    my $good = Chart::Plotly::Image::Orca::orca(
        #<<< no perltidy
                plot => $plotly,
                file => $filename,
        maybe   width => $opts->{width},
        maybe   height => $opts->{height},
        #>>>
    );
    die "Failed to save image via plotly-orca" unless $good;
}

1;

__END__

=head1 DESCRIPTION

The Plotly backend for Chart::GGPlot.

=head1 SEE ALSO

L<https://plot.ly/|Plotly>

L<Chart::GGPlot::Backend>, L<Chart::Plotly>

