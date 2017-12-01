# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ExportPlugin is Copyright (C) 2017 Michael Daum http://michaeldaumconsulting.com
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details, published at
# http://www.gnu.org/copyleft/gpl.html

package Foswiki::Plugins::ExportPlugin;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Contrib::JsonRpcContrib ();

our $VERSION = '0.03';
our $RELEASE = '01 Dec 2017';
our $SHORTDESCRIPTION = 'Export wiki content in various formats';
our $NO_PREFS_IN_TOPIC = 1;

sub completePageHandler {
  $_[0] =~  s/\%(?:START|STOP|BEGIN|END)EXPORT\%//g;
}

sub initPlugin {

  Foswiki::Func::registerRESTHandler('html',
    sub { 
      require Foswiki::Plugins::ExportPlugin::Html;
      my $exporter = Foswiki::Plugins::ExportPlugin::Html->new();
      return $exporter->export(@_);
    },
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Func::registerRESTHandler('pdf',
    sub { 
      require Foswiki::Plugins::ExportPlugin::Pdf;
      my $exporter = Foswiki::Plugins::ExportPlugin::Pdf->new();
      return $exporter->export(@_);
    },
    authenticate => 1,
    validate => 1,
    http_allow => 'GET,POST',
  );

  Foswiki::Contrib::JsonRpcContrib::registerMethod("ExportPlugin", "pdf", sub {
    require Foswiki::Plugins::ExportPlugin::Pdf;
    my $exporter = Foswiki::Plugins::ExportPlugin::Pdf->new();
    return $exporter->jsonRpcExport(@_);
  });


  return 1;
}

1;
