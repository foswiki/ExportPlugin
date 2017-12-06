# ---+ Extensions
# ---++ ExportPlugin
# This is the configuration used by the <b>ExportPlugin</b>.

# **STRING**
$Foswiki::cfg{ExportPlugin}{Dir} = '$Foswiki::cfg{PubDir}/export';

# **STRING**
$Foswiki::cfg{ExportPlugin}{URL} = '$Foswiki::cfg{DefaultUrlHost}$Foswiki::cfg{PubUrlPath}/export';

# **STRING**
$Foswiki::cfg{ExportPlugin}{BaseURL} = '$Foswiki::cfg{PubDir}/export';

# **BOOLEAN**
$Foswiki::cfg{ExportPlugin}{Debug} = 0;

# **BOOLEAN**
$Foswiki::cfg{ExportPlugin}{ForceSSL} = 1;

# **PATH**
$Foswiki::cfg{ExportPlugin}{PdfCmd} = '/usr/local/bin/weasyprint --base-url %BASEURL|U% --media-type print --encoding utf-8 %INFILE|F% %OUTFILE|F%';

# **PATH**
$Foswiki::cfg{ExportPlugin}{PdfJamCmd} = '/usr/bin/pdfjam --quiet --fitpaper true --rotateoversize true --outfile %OUTFILE|F% %FILES|F% ';

# ---++ JQueryPlugin
# ---+++ Extra plugins
# **STRING**
$Foswiki::cfg{JQueryPlugin}{Plugins}{PdfExport}{Module} = 'Foswiki::Plugins::ExportPlugin::JQueryPdfExport';

# **BOOLEAN**
$Foswiki::cfg{JQueryPlugin}{Plugins}{PdfExport}{Enabled} = 1;


1;
