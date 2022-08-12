# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ExportPlugin is Copyright (C) 2020 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ExportPlugin::Excel;

use strict;
use warnings;

use Foswiki::Func ();
use Foswiki::Form ();
use Foswiki::Plugins::ExportPlugin::Exporter ();
use Spreadsheet::Write ();
use File::Path qw(make_path);

our @ISA = qw( Foswiki::Plugins::ExportPlugin::Exporter );

sub new {
  my $class = shift;

  my $this = bless($class->SUPER::new(@_), $class);

  return $this;
}

sub getFileName {
  my ($this, $web, $topic, $rev, $name) = @_;

  my $file = $this->param("filename");
  $file ||= 'genexcel_' . ($name || $topic || $web) . ($rev ? "_$rev" : "");
  $file =~ s/\.xlsx?$//;
  $file .= '.xlsx';

  $file =~ s{[\\/]+$}{};
  $file =~ s!^.*[\\/]!!;
  $file =~ s/$Foswiki::regex{filenameInvalidCharRegex}//g;

  return $file;
}

sub needsUpdate {
  return 1;
}

sub getTargetPath {
  my ($this, $w, $t, $rev, $name) = @_;

  my $web = $this->{baseSession}->{webName};
  my $topic = $this->{baseSession}->{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  my $path = $Foswiki::cfg{PubDir};
  $path .= '/' . $web if defined $web;
  $path .= '/' . $topic if defined $topic;

  make_path($path, {
    mode => $Foswiki::cfg{Store}{dirPermission}
  });
  my $file = $path . '/' . $this->getFileName($web, $topic, $rev, $name);

  return wantarray ? ($path, $file) : $file;
}

sub getTargetUrl {
  my ($this, $w, $t, $rev, $name) = @_;

  my $web = $this->{baseSession}->{webName};
  my $topic = $this->{baseSession}->{topicName};
  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);

  my $file = $this->getFileName($web, $topic, $rev, $name);
  return Foswiki::Func::getPubUrlPath($web, $topic, $file, absolute => 1) . '?t='.time();
}

sub preProcess {
  my $this = shift;

  $this->SUPER::preProcess();

  my @fields = split(/\s*,\s*/, $this->param("fields") || '');
  $this->{_fields} = \@fields;

  $this->writeDebug("fields=" . join(", ", sort @fields));
}

sub exportTopic {
  my ($this, $web, $topic, $rev) = @_;

  my ($meta, $text) = Foswiki::Func::readTopic($web, $topic, $rev);
  my ($date, $author);
  ($date, $author, $rev) = $meta->getRevisionInfo();

  my $wikiName = Foswiki::Func::getWikiName();
  my $cUID = Foswiki::Func::getCanonicalUserID();

  unless ($meta->haveAccess("VIEW", $cUID)) {
    $this->writeWarning("$wikiName has got no access to $web.$topic ... skipping");
    return 0;
  }

  my $formName = $meta->getFormName();
  unless ($formName) {
    $this->writeWarning("no form in $web.$topic ... skipping");
    return 0;
  }

  my $formDef = $this->getFormDef($web, $formName);
  unless ($formDef) {
    $this->writeWarning("form definition $formName not found ... skipping");
    return 0;
  }

  my @fields = ();
  foreach my $fieldName (@{$this->{_fields}}) {
    my $fieldDef;
    if ($fieldName eq 'url') {
      $fieldDef = {
        name => 'url',
        title => 'Url',
        size => 130,
        _value => Foswiki::Func::getScriptUrl($web, $topic, "view")
      };
    } elsif ($fieldName eq 'text') {
      $fieldDef = {
        name => 'text',
        title => 'Text',
        size => 130,
        _value => $text,
      };
    } elsif ($fieldName eq 'topic') {
      $fieldDef = {
        name => 'topic',
        title => 'Topic',
        size => 30,
        _value => $topic,
      };
    } elsif ($fieldName eq 'web') {
      $fieldDef = {
        name => 'web',
        title => 'Web',
        size => 30,
        _value => $web,
      };
    } elsif ($fieldName eq 'revision') {
      $fieldDef = {
        name => 'revision',
        title => 'Revision',
        size => 30,
        _value => $rev,
      };
    } elsif ($fieldName eq 'workflowstate') {
      $fieldDef = {
        name => 'workflowstate',
        title => 'Workflow',
        size => 30,
        _value => '',
      };
    } elsif ($fieldName eq 'qmstate') {
      $fieldDef = {
        name => 'qmstate',
        title => 'Status',
        size => 30,
        _value => '',
      };
    } elsif ($fieldName eq 'author') {
      my $val = Foswiki::Func::getWikiName($author);
      $val = Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $val) if $val;

      $fieldDef = {
        name => 'author',
        title => 'Author',
        size => 30,
        _value => $val || 'unknown',
      };
    } elsif ($fieldName eq 'modified' || $fieldName eq 'date') {
      my $val = Foswiki::Time::formatTime($date, '$day $mon $year - $hour:$min');
      $fieldDef = {
        name => 'date',
        title => 'Date',
        size => 30,
        _value => $val,
      };
    } else {
      $fieldDef = $formDef->getField($fieldName);
      unless (defined $fieldDef) {
        $this->writeWarning("field $fieldName not found in form $formName");
        next;
      }
    }
    push @fields, $fieldDef;
  }

  # only executed the first time
  my $file = $this->getTargetPath($web, $topic, $rev);
  $this->writeDebug("file=$file");
  unless (defined $this->{_sp}) {
    $this->{_sp} = Spreadsheet::Write->new(
      file => $file,
      styles => {
        header => {font_weight => 'bold'},
      }
    );

    # write header
    my @headerRow = ();
    foreach my $fieldDef (@fields) {
      my $name = $fieldDef->{name};
      my $title = $this->param($name . "_title") || $fieldDef->{title} || $name;
      my $width = $fieldDef->{size} || 20;
      $width =~ s/^\s*(\d+).*$/$1/;
      $width = 20 if $width < 20;
      $title =~ s/<nop>//g;

      $this->writeDebug("name=$name, header=$title, width=$width");
      push @headerRow,
        {
        content => $this->translate($title),
        style => "header",
        width => $width,
        };
    }
    $this->{_sp}->addrow(@headerRow);
  }

  my @row = ();
  foreach my $fieldDef (@fields) {
    my $fieldValue;
    if (ref($fieldDef) =~ 'Foswiki::Form') {
      $fieldValue = $meta->get('FIELD', $fieldDef->{name});
      $fieldValue = $fieldValue->{value} if defined $fieldValue;

      # get default value
      unless (defined $fieldValue && $fieldValue ne "") {
        if ($fieldDef->can('getDefaultValue')) {
          $fieldValue = $fieldDef->getDefaultValue() // '';
        }
      }

      # user topics
      if ($fieldDef->{name} =~ /^(Author|Creator|info\.author|createauthor|publishauthor|qmstate\.(?:pendingReviewers|reviewers))$/ || ($fieldDef && $fieldDef->{type} eq "user")) {
        my @val = ();
        foreach my $item (split(/\s*,\s*/, $fieldValue)) {
          if (Foswiki::Func::topicExists($Foswiki::cfg{UsersWebName}, $item)) {
            push @val, Foswiki::Func::getTopicTitle($Foswiki::cfg{UsersWebName}, $item);
          } else {
            push @val, $item;
          }
        }
        $fieldValue = join(", ", @val);
      }

      # dates
      elsif ($fieldDef->{type} =~ /date|\+values/) {
        $fieldValue = $fieldDef->getDisplayValue($fieldValue);
      }

      # topic references
      elsif ($fieldDef->{type} =~ /topic|cat/) {
        my @val = ();
        # TODO: better category handling
        foreach my $item (split(/\s*,\s*/, $fieldValue)) {
          if (Foswiki::Func::topicExists($web, $item)) {
            push @val, Foswiki::Func::getTopicTitle($web, $item);
          } else {
            push @val, $item;
          }
        }
        $fieldValue = join(", ", @val);
      }
    } else {
      # virtual fields
      if ($fieldDef->{name} eq 'qmstate') {
        require Foswiki::Plugins::QMPlugin;
        my $state = Foswiki::Plugins::QMPlugin->getCore->getState($web, $topic);
        $fieldValue = $state ? $this->translate($state->getCurrentNode->prop("title")) : '';
      } elsif ($fieldDef->{name} eq 'workflowstate') {
        my $workflow = $meta->get("WORKFLOW");
        $fieldValue = $workflow ? $this->translate($workflow->{name}) : '';
      } else {
        $fieldValue = $fieldDef->{_value};
      }
    }

    unless (defined $fieldValue) {
      $this->writeWarning("field $fieldDef->{name} has got an undefined value");
      $fieldValue ||= 'undef';
    }

    #$this->writeDebug("$fieldDef->{name}=$fieldValue");

    push @row, $fieldValue;
  }

  #$this->writeDebug("adding row ",join(", ", @row));

  $this->{_sp}->addrow({content => \@row});

  return 1;
}

sub postProcess {
  my $this = shift;

  if ($this->{_sp}) {
    $this->{_sp}->close();
  } else {
    $this->writeWarning("no excel file created");
  }

  return $this->getTargetUrl();
}

1;
