# Plugin for Foswiki - The Free and Open Source Wiki, http://foswiki.org/
#
# ExportPlugin is Copyright (C) 2017-2020 Michael Daum http://michaeldaumconsulting.com
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

package Foswiki::Plugins::ExportPlugin::Exporter;

use strict;
use warnings;

use Foswiki ();
use Foswiki::Func ();
use Foswiki::Form ();
use Foswiki::Request ();
use Foswiki::Plugins ();
use Time::HiRes ();
use File::Spec();
use File::Copy();
use File::Path qw(make_path);
use Data::Dump qw(dump);
use Error qw(:try);

sub new {
  my $class = shift;

  my $this = bless({
      debug => $Foswiki::cfg{ExportPlugin}{Debug},
      exportDir => $Foswiki::cfg{ExportPlugin}{Dir},
      exportUrl => $Foswiki::cfg{ExportPlugin}{URL},
      baseUrl => $Foswiki::cfg{ExportPlugin}{BaseURL},
      @_
    },
    $class
  );

  $this->{startTime} = $this->{lapseTime} = $this->getTime;
  $this->{urlOfAsset} = {};
  $this->{params} = {};

  $this->{assetsDir} = $this->{exportDir} . '/assets';
  $this->{assetsUrl} = $this->{exportUrl} . '/assets';

  $this->{htmlDir} = $this->{exportDir} . '/html';
  $this->{htmlUrl} = $this->{exportUrl} . '/html';

  $this->{baseUrl} ||= $this->{exportUrl};
  $this->{baseUrl} .= '/' unless $this->{baseUrl} =~ /\/$/;

  return $this;
}

sub params {
  my $this = shift;
  my $params = shift;

  if (defined $params) {
    $this->{params} = $params;
  }

  return $this->{params};
}

sub param {
  my ($this, $key) = @_;

  my $val = $this->{params}{$key};

  unless (defined $val) {
    my $request = Foswiki::Func::getRequestObject();
    $val = $request->param($key);
  }

  return $val;
}

sub param_list {
  my ($this) = @_;

  my $request = Foswiki::Func::getRequestObject();
  my @keys = $request->param();

  return @keys;
}

sub writeDebug {
  my ($this, $msg) = @_;

  return unless $this->{debug};
  return unless $msg;

  $msg = dump($msg) . "\n" if ref($msg);

  #Foswiki::Func::writeDebug(__PACKAGE__ . " - $msg");
  print STDERR __PACKAGE__ . " - $msg\n";
}

sub writeWarning {
  my ($this, $msg) = @_;

  #Foswiki::Func::writeWarning(__PACKAGE__ . " - $msg");
  print STDERR __PACKAGE__ . " - WARNING: $msg\n";
}

sub getTime {
  my $this = shift;

  return [Time::HiRes::gettimeofday];
}

sub getElapsedTime {
  my ($this, $since) = @_;

  my $startTime;
  my $endTime = $this->getTime();

  if ($since) {
    $startTime = $since;
  } else {
    $startTime = $this->{lapseTime};
    $this->{lapseTime} = $endTime;
  }

  return (Time::HiRes::tv_interval($startTime, $endTime) * 10000);
}

# rest interface
sub export {
  my ($this, $session, $subject, $verb, $response) = @_;

  $this->writeDebug("called export()");

  my $base = $this->param("base");
  $this->{baseUrl} = $base if defined $base;

  my $result = '';

  my $web = $this->param("web");
  my $topics = $this->param("topics") || $this->param("topic");
  my @topics = ();

  if (defined $web) {
    if (defined $topics) {
      @topics = split(/\s*,\s*/, $topics);
    } else {
      @topics = Foswiki::Func::getTopicList($web);
    }
    $result = $this->exportTopics($web, \@topics);
  } else {
    if (defined $topics) {
      $web = $session->{webName};
      @topics = split(/\s*,\s*/, $topics);
      $result = $this->exportTopics($web, \@topics);
    } else {
      my $webs = $this->param("webs");
      my @webs = ();
      my $include = $this->param("includeweb");
      my $exclude = $this->param("excludeweb");
      if (defined $webs) {
        @webs = split(/\s*,\s*/, $webs);
      } else {
        @webs = Foswiki::Func::getPublicWebList();
      }
      foreach my $web (sort @webs) {
        next if defined $include && $web !~ /$include/;
        next if defined $exclude && $web =~ /$exclude/;
        $web =~ s/\./\//g;
        $this->writeDebug("exporting $web");
        @topics = Foswiki::Func::getTopicList($web);
        $result = $this->exportTopics($web, \@topics);
      }
    }
  }

  #$this->writeDebug("exporting took ".$this->getElapsedTime($this->{startTime}));

  if (Foswiki::Func::isTrue($this->param("redirect"), 0)) {
    $this->writeDebug("redirecting to $result");
    my $request = Foswiki::Func::getRequestObject();
    Foswiki::Func::redirectCgiQuery($request, $result);
  }

  return $result;
}

# jsonrpc interface
sub jsonRpcExport {
  my ($this, $session, $request) = @_;

  $this->writeDebug("called jsonRpcExport()");

  # init params
  $this->params($request->params());

  my $web = $this->param("web") || $session->{webName};
  my $topics = $this->param("topics") || $this->param("topic") || $this->param("Topic") || '';
  my @topics = split(/\s*,\s*/, $topics);

  $this->writeDebug(\@topics);

  my $result = $this->exportTopics($web, \@topics);

  return {
    msg => $this->{_numExported} . " topic(s) have been successfully exported.",
    redirectUrl => $result,
  };
}

sub needsUpdate {
  my ($this, $web, $topic, $rev) = @_;

  return 1 if Foswiki::Func::isTrue($this->param("forceupdate"), 0);

  my $src = $Foswiki::cfg{DataDir} . '/' . $web . '/' . $topic . '.txt';    # SMELL;
  my $dst = $this->getTargetPath($web, $topic, $rev);
  my $mtimeSrc = (stat $src)[9] || 0;
  my $mtimeDst = (stat $dst)[9] || 0;

  if ($mtimeSrc < $mtimeDst) {
    $this->writeDebug("skipping $web.$topic ... did not change");
    return 0;
  }

  return 1;
}

sub exportTopics {
  my ($this, $web, $topics) = @_;

  my $include = $this->param("include");
  my $exclude = $this->param("exclude");

  @$topics = grep { /$include/ } @$topics if defined $include;
  @$topics = grep { !/$exclude/ } @$topics if defined $exclude;

  my $i = 0;
  my $limit = $this->param("limit") || 0;
  if ($limit) {
    @$topics = splice(@$topics, 0, $limit);
  }

  my $publishSet = $this->publishSet($web, $topics);

  # this to do before export starts
  $this->preProcess();

  my $len = scalar(@$topics);
  $this->writeDebug("exporting $len topic(s)");

  # capture main session running the rest handler
  $this->{baseSession} ||= $Foswiki::Plugins::SESSION;

  $this->{_numExported} = 0;
  foreach my $item (@$publishSet) {
    $i++;

    my $needsUpdate = $this->needsUpdate($item->{web}, $item->{topic}, $item->{rev});
    $this->writeDebug("needsUpdate=$needsUpdate, topic=$item->{web}.$item->{topic}");
    next unless $needsUpdate;

    unless (Foswiki::Func::topicExists($item->{web}, $item->{topic})) {
      $this->writeWarning("$item->{web}.$item->{topic} does not exist ... skipping");
      next;
    }

    # pushTopicContext does not suffice. we need a new Foswiki session for every topic
    # Foswiki::Func::pushTopicContext($item->{web}, $item->{topic});

    my $request = Foswiki::Request->new();

    # forward params
    foreach my $key ($this->param_list) {
      next if $key =~ /^(web|topic|rev|redirect|forceupdate|include|exclude|includeweb|excludeweb|limit|debug|redirect)$/;
      my $val = $this->param($key);
      $request->param($key, $val);
    }
    $request->param("topic", $item->{web} . '.' . $item->{topic});
    $request->param("rev", $item->{rev}) if $item->{rev};

    my $wikiName = Foswiki::Func::getWikiName();
    my $loginName = Foswiki::Func::wikiToUserName($wikiName);
    my $session = Foswiki->new(
      $loginName,
      $request,
      {
        static => 1,
      }
    );

    # patch internal session
    $Foswiki::Plugins::SESSION = $session;

    $this->writeDebug("$i/$len: exporting $item->{web}.$item->{topic}, rev=$item->{rev}");
    $this->{_numExported} += ($this->exportTopic($item->{web}, $item->{topic}, $item->{rev}) ? 1 : 0);

    $session->finish();

    # revert to main session
    $Foswiki::Plugins::SESSION = $this->{baseSession};

    last if $limit && $i > $limit;
  }

  # restore main session context;
  $Foswiki::Plugins::SESSION = $this->{baseSession};

  # this to do after export stoped
  return $this->postProcess();
}

sub publishSet {
  my ($this, $web, $topics) = @_;

  if ($topics) {
    $this->{_publishSet} = [];
    foreach my $topic (@$topics) {
      my $rev;
      if ($topic =~ /^(.*?)(?:=(\d+))?$/) {
        $topic = $1;
        $rev = $2;
      }
      $rev ||= 0;
      my ($thisWeb, $thisTopic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
      $thisWeb =~ s/\//\./g;
      push @{$this->{_publishSet}},
        {
        web => $thisWeb,
        topic => $thisTopic,
        rev => $rev
        };
    }
  }

  return $this->{_publishSet};
}

sub preProcess {
  my ($this) = @_;

  my $debug = $this->param("debug");
  $this->{debug} = Foswiki::Func::isTrue($debug, 0) if defined $debug;
}

sub postProcess {
  my ($this) = @_;

  my $item = @{$this->publishSet()}[0];

  return $this->getTargetUrl($item->{web}, $item->{topic}, $item->{rev});
}

sub exportTopic {
  my ($this, $web, $topic, $rev) = @_;

  # not using a die()
  $this->writeWarning("exportTopic not implemented");
}

sub getTargetPath {
  my ($this, $web, $topic, $rev, $name) = @_;

  # not using a die()
  $this->writeWarning("getTargetPath not implemented");
}

sub getTargetUrl {
  my ($this, $web, $topic, $rev, $name) = @_;

  # not using a die()
  $this->writeWarning("getTargetUrl not implemented $this");
}

sub getFormDef {
  my ($this, $web, $topic) = @_;

  ($web, $topic) = Foswiki::Func::normalizeWebTopicName($web, $topic);
  return unless defined $web && defined $topic;

  my $session = $Foswiki::Plugins::SESSION;

  my $formDef;
  try {
    $formDef = new Foswiki::Form($session, $web, $topic);
  } catch Error with {
    $this->writeWarning("getFormDef() failed for $web.$topic");
  };

  return $formDef;
}

sub extractExportableAreas {
  my ($this, $text) = @_;

  my $newText = '';
  my $seen = 0;
  my $inside = 1;
  foreach my $s (split(/(%(?:START|BEGIN)EXPORT%|%(?:STOP|END)EXPORT%)/, $text)) {
    if ($s =~ /^%(?:START|BEGIN)EXPORT%$/) {
      $newText = '' unless $seen;
      $inside = 1;
      $seen = 1;
    } elsif ($s =~ /^%(?:STOP|END)EXPORT%$/) {
      $inside = 0;
      $seen = 1;
    } else {
      $newText .= $s if $inside;
    }
  }

  return $newText;
}

sub readTemplate {
  my ($this, $web, $topic, $meta) = @_;

  my $skin = $this->param("skin");
  $this->writeDebug("skin=" . ($skin || ''));

  my $template;
  $template = Foswiki::Func::getPreferencesValue('VIEW_TEMPLATE');
  $this->writeDebug("prefs template=" . ($template || ''));
  $template = $meta->getPreference("VIEW_TEMPLATE");
  $this->writeDebug("topic template=" . ($template || ''));

  if (!$template && $Foswiki::cfg{Plugins}{AutoTemplatePlugin}{Enabled}) {
    require Foswiki::Plugins::AutoTemplatePlugin;
    $template = Foswiki::Plugins::AutoTemplatePlugin::getTemplateName($web, $topic, 'print');
    $this->writeDebug("auto template=" . ($template || ''));
  }
  $template ||= "view";

  $this->writeDebug("template=$template");

  my $result = Foswiki::Func::readTemplate($template, $skin);
  $result = Foswiki::Func::readTemplate("view", $skin) unless $result;

  return $result;
}

sub renderHTML {
  my ($this, $web, $topic, $meta, $text) = @_;

  my $session = $Foswiki::Plugins::SESSION;

  $text = $this->extractExportableAreas($text);
  #$this->writeDebug("text=$text");

  my $result = $this->readTemplate($web, $topic, $meta);
  $result =~ s/\%TEXT\%/$text/g;
  $result = $meta->expandMacros($result);
  $result = $meta->renderTML($result);

  if ($session->{cache}) {
    $session->{cache}->renderDirtyAreas(\$result);
  }

  if ($session->{plugins}) {
    $session->{plugins}->dispatch('completePageHandler', $result, '');
  }

  # do the zones
  $result = $this->renderZones($result);

  # cleanup stuff
  $result =~ s/<nop>//g;
  $result =~ s/<\/?noautolink>//g;
  $result =~ s/<!--[^\[<].*?-->//g;
  $result =~ s/^\s*$//gms;
  $result =~ s/<p><\/p>\s*([^<>]+?)\s*(?=<p><\/p>)/<p class='p'>$1<\/p>\n\n/gs;
  $result =~ s/\s*<\/p>(?:\s*<p><\/p>)*/<\/p>\n/gs;    # remove useless <p>s
  $result =~ s/\%\{(<pre[^>]*>)\}&#37;\s*/$1/g;
  $result =~ s/\s*&#37;\{(<\/pre>)\}\%/$1/g;

  # clean up unsatisfied WikiWords.
  $result =~ s/<([^\s]+)\s+[^>]*?class=.foswikiNewLink.[^>]*?>(.*?)<\/\1>/$2/g;

  my $pub = Foswiki::Func::getPubUrlPath();
  my $request = Foswiki::Func::getRequestObject();
  my $host = $session->{urlHost} || $request->header('Host') || 'localhost';

  # remove non-macros and leftovers
  $result =~ s/%(?:REVISIONS|REVTITLE|REVARG|QUERYPARAMSTRING)%//g;
  $result =~ s/^%META:\w+{.*}%$//gm;

  # copy assets and rewrite urls
  $result =~ s!(['"\(])($Foswiki::cfg{DefaultUrlHost}|https?://$host)?$pub/(.*?)(\1|\))!$1.$this->copyAsset($3).$4!ge;

  # rewrite view links
  $result = $this->rewriteViewLinks($result);

  # convert absolute to relative urls
  $result =~ s/$host//g;

  # fix anchors
  $result =~ s!href=(["'])\?.*?#!href=$1#!g;

  # remove <base.../> tag
#  $result =~ s/<\!\-\-\[if IE\]><\/base><!\[endif\]\-\->//i;
#  $result =~ s/<base[^>]+>.*?<\/base>//i;
#  $result =~ s/<base[^>]+\/?>//i;
#  $result =~ s/<\/base>//i;

  return $result;
}

sub toFileUrl {
  my ($this, $url) = @_;

  my $fileUrl = $url;
  my $localServerPattern = '^(?:' . $Foswiki::cfg{DefaultUrlHost} . ')?' . $Foswiki::cfg{PubUrlPath} . '(.*)$';
  $localServerPattern =~ s/https?/https?/;

  if ($fileUrl =~ /$localServerPattern/) {
    $fileUrl = $1;
    $fileUrl =~ s/\?.*$//;
    $fileUrl = "file://" . $Foswiki::cfg{PubDir} . $fileUrl;
  } else {
    #writeDebug("url=$url does not point to a local asset (pattern=$localServerPattern)");
  }

  #writeDebug("url=$url, fileUrl=$fileUrl");
  return $fileUrl;
}

sub rewriteViewLinks {
  my ($this, $html) = @_;

  my $session = $Foswiki::Plugins::SESSION;
  my $request = Foswiki::Func::getRequestObject();
  my $host = $session->{urlHost} || $request->header('Host') || 'localhost';
  my $viewUrl = $session->getScriptUrl(1, "view");
  my $viewUrlPath = $viewUrl;
  $viewUrlPath =~ s/^$host//g;

  #$this->writeDebug("host=$host, viewUrl=$viewUrl, viewUrlPath=$viewUrlPath");

  our %topics;
  foreach my $item (@{$this->publishSet}) {
    $topics{"$item->{web}.$item->{topic}"} = 1;
  }
  #print STDERR "converging topics ".join(", ", keys %topics)."\n";

  sub _doit {
    my ($this, $all, $quote, $web, $topic, $params) = @_;

    return $all unless $topics{"$web.$topic"};

    #print STDERR "rewriting web=$web, topic=$topic\n";

    my $url = $this->getTargetUrl($web, $topic);
    $url ||= '?' . $params if $params;
    return 'href=' . $quote . $url . $quote;
  }

  $html =~ s!(href=(["'])(?:$viewUrl|$viewUrlPath)/($Foswiki::regex{webNameRegex})(?:\.|/)([[:upper:]]+[[:alnum:]]*)(\?.*?)?\2)!_doit($this, $1, $2, $3, $4, $5)!ge;

  return $html;
}

sub copyAsset {
  my ($this, $assetName) = @_;

  $assetName = _urlDecode($assetName);
  $assetName =~ s/^\s+|\s+$//g;
  $assetName =~ s/\?.*$//;

  my $url = $this->{urlOfAsset}{$assetName};
  return $url if defined $url;

  my $path = "";
  my $file = $assetName;
  if ($assetName =~ /^(.*)\/(.*?)$/) {
    $path = $1;
    $file = $2;
  }

  my $newPath = $this->{assetsDir} . '/' . $path;
  my $src = Foswiki::Func::getPubDir() . '/' . $assetName;
  my $dst = $newPath . '/' . $file;

  # collapse relative links
  while ($src =~ s/([^\/\.]+\/\.\.\/)//) { 1; }
  while ($dst =~ s/[^\/\.]+\/\.\.\///) { 1; }
  $src =~ s/\/+/\//g;
  $dst =~ s/\/+/\//g;

  $url = $this->{assetsUrl} . '/' . $path . '/' . $file;
  #$url = $path.'/'.$file;

  #print STDERR "assetName=$assetName, src=$src, dst=$dst\n";

  if (-r $src) {

    unless (-d $newPath) {
      $this->writeDebug("... creating path $newPath");
      make_path($newPath);
    }

    $this->mirrorFile($src, $dst);
    #$this->mirrorFile($src.',v', $dst.',v');
    $this->mirrorFile($src . '.gz', $dst . '.gz') if $src =~ /\.(css|js)$/;

    $this->{urlOfAsset}{$assetName} = $url;
  } else {
    #$this->writeDebug("... src=$src, dst=$dst, url=$url");
    $this->writeWarning("$src is not readable");
  }

  # check css for additional resources, ie, url()
  if ($assetName =~ /\.css$/) {
    my %moreAssets = ();

    my $data = Foswiki::Func::readFile($src);
    #$this->writeDebug("... reading file $src");
    $data =~ s#\/\*.*?\*\/##gs;

    foreach my $asset (split(/;/, $data)) {
      while ($asset =~ /url\(["']?(.*?)["']?\)/g) {
        my $url = $1;
        next if $url =~ /^data:image/;
        $url =~ s/\?.*$//;
        $url =~ s/#.*$//;
        next if $moreAssets{$url};
        #$this->writeDebug("... found more assets in $file: $asset");
        $moreAssets{$url} = 1;
      }
    }

    my $pub = Foswiki::Func::getPubUrlPath();
    foreach my $asset (keys %moreAssets) {

      unless ($asset =~ /^https?/) {

        if ($asset !~ m!^/!) {
          $asset = $path . '/' . $asset;
        } else {
          if ($asset =~ m!$pub/(.*)!) {
            my $old = $asset;
            $asset = $1;
          }
        }

        $this->copyAsset($asset);
      }
    }
  }

  return $url;
}

sub mirrorFile {
  my ($this, $src, $dst) = @_;

  return unless -e $src;

  my $forceUpdate = Foswiki::Func::isTrue($this->param("forceupdate"), 0);

  my $mtimeSrc = (stat $src)[9];
  my $mtimeDst = (stat $dst)[9];

  if (!-e $dst || $forceUpdate || $mtimeSrc > $mtimeDst) {
    #$this->writeDebug("... copying file $src to $dst");
    File::Copy::copy($src, $dst) || $this->writeWarning("copying $src to $dst failed: $!");
  }
}

sub renderZones {
  my ($this, $text) = @_;

  # SMELL: call to unofficial api
  my $session = $Foswiki::Plugins::SESSION;
  if ($session->can("_renderZones")) {    # old foswiki
    $text = $session->_renderZones($text);
  } else {
    $text = $session->zones()->_renderZones($text);
  }

  return $text;
}

sub translate {
  my ($this, $string, $web, $topic) = @_;

  my $result = $string;

  $string =~ s/^_+//;    # strip leading underscore as maketext doesnt like it

  my $context = Foswiki::Func::getContext();
  if ($context->{'MultiLingualPluginEnabled'}) {
    require Foswiki::Plugins::MultiLingualPlugin;
    $result = Foswiki::Plugins::MultiLingualPlugin::translate($string, $web, $topic);
  } else {
    my $session = $Foswiki::Plugins::SESSION;
    $result = $session->i18n->maketext($string);
  }

  $result //= $string;

  return $result;
}

sub _urlDecode {
  my $text = shift;

  $text = Foswiki::encode_utf8($text);
  $text =~ s/%([\da-fA-F]{2})/chr(hex($1))/ge;
  $text = Foswiki::decode_utf8($text);

  return $text;
}

1;
