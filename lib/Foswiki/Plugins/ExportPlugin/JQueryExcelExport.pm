# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
# 
# Copyright (C) 2020 Michael Daum, http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ExportPlugin::JQueryExcelExport;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Plugins::JQueryPlugin::Plugin ();
our @ISA = qw( Foswiki::Plugins::JQueryPlugin::Plugin );

use constant TRACE => 0; # toggle me

=begin TML

---+ package Foswiki::Plugins::ExportPlugin::JQueryExcelExport

This is the perl stub for the jquery.excelExport plugin.

=cut

=begin TML

---++ ClassMethod new( $class, $session, ... )

Constructor

=cut

sub new {
  my $class = shift;
  my $session = shift || $Foswiki::Plugins::SESSION;

  my $this = bless($class->SUPER::new( 
    $session,
    name => 'ExcelExport',
    version => '1.00',
    author => 'Michael Daum',
    homepage => 'http://foswiki.org/Extensions/ExportPlugin',
    puburl => '%PUBURLPATH%/%SYSTEMWEB%/ExportPlugin',
    documentation => "$Foswiki::cfg{SystemWebName}.ExportPlugin",
    javascript => ['jquery.excelexport.js'],
    i18n => $Foswiki::cfg{SystemWebName} . "/ExportPlugin/i18n",
    css => ['style.css'],
    dependencies => ['i18n', 'blockui', 'jsonrpc', 'ui'], 
  ), $class);

  return $this;
}

1;
