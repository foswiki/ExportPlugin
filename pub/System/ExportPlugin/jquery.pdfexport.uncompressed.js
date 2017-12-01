/*
 * jQuery pdf export plugin 1.0
 *
 * Copyright (c) 2017 Michael Daum http://michaeldaumconsulting.com
 *
 * Dual licensed under the MIT and GPL licenses:
 *   http://www.opensource.org/licenses/mit-license.php
 *   http://www.gnu.org/licenses/gpl.html
 *
 */

"use strict";
(function($) {

  // Create the defaults once
  var defaults = {
        debug: false
      };


  // The actual plugin constructor 
  function PdfExport(elem, opts) { 
    var self = this;

    self.$elem = $(elem); 
    self.$form = self.$elem.find("form:first");
    self.$progressbar = self.$elem.find(".jqPdfExportProgress");

    self.opts = $.extend({}, defaults, opts, self.$elem.data()); 
    self.init(); 
  } 

  // logging
  PdfExport.prototype.log = function() {
    var self = this, args;

    if (!console || !self.opts.debug) {
      return;
    }

    args = $.makeArray(arguments);
    args.unshift("PDF-EXPORT:");
    console.log.apply(console, args);
  };

  // warning
  PdfExport.prototype.warn = function() {
    var self = this, args;

    if (!console) {
      return;
    }

    args = $.makeArray(arguments);
    args.unshift("PDF-EXPORT:");
    console.warn.apply(console, args);
  };

  PdfExport.prototype.tickProgress = function(text) {
    var self = this,
        label = self.$progressbar.find("label"),
        val = ((self._index++) / self._length) * 100;

    label.html($.i18n("Processing %label% ...", {
      label: text
    }));

    self.$progressbar.progressbar("value", val);
  };

  PdfExport.prototype.initQueue = function(items) {
    var self = this;

    self._queue = items;
    self._index = 0;
    self._length = items.length;
    self.$progressbar.progressbar("value", 0);
    self.$progressbar.show();
  };

  // process queue of topics to be rendered to pdf
  PdfExport.prototype.processQueue = function(params) {
    var self = this;

    return $.Deferred(function(dfd) {
      var item = self._queue.shift();

      if (item) {
        self.tickProgress(item);
        params.Topic = item;

        self.log("submitting to backend params=",params);

        $.jsonRpc(
          foswiki.getScriptUrlPath("jsonrpc"), {
            namespace: "ExportPlugin",
            method: "pdf",
            id: "export1",
            params: params
          }).then(function() {
            self.processQueue(params).then(function() {
              dfd.resolve();
            });
          }).fail(function(xhr, textStatus, err) {
              dfd.reject(xhr, textStatus, err);
          });
      } else {
        dfd.resolve();
      }
    }).promise();
  };


  // init form
  PdfExport.prototype.init = function() {
    var self = this;

    // init progress bar
    self.$progressbar.progressbar();

    // add submit handler
    self.$form.on("submit", function(e) {
      var params, origTopics;

      e.preventDefault();

      // Disable the submit button to prevent repeated clicks
      self.$form.block({message:''});
      self.hideMessages();

      params = self.serializeForm();

      if (self.validate(params)) {
        // submit valid form

        origTopics = params.Topic;
        self.initQueue(params.Topic.split(/\s*,\s*/));
        self.processQueue(params)
          .then(function() {
            self.$progressbar.hide();
            params.Topic = origTopics;
            params.join = 1;

            self.log("submitting to backend params=",params);
            
            $.jsonRpc(
              foswiki.getScriptUrlPath("jsonrpc"), {
                namespace: "ExportPlugin",
                method: "pdf",
                id: "export1",
                params: params,
                error: function(resp, textStatus, xhr) {
                  self.showMessage("error", resp.error.message, $.i18n("Error"));
                  self.warn("ERROR: code="+resp.error.code+", "+resp.error.message);
                  self.$form.unblock();
                  self.$progressbar.hide();
                },
                success: function(resp, textStatus, xhr) {
                  self.$form.unblock();
                  self.hideMessages();
                  if (typeof(resp.result.redirectUrl) !== 'undefined') {
                    window.location.href = resp.result.redirectUrl;
                    //console.log("redirecting to",resp.result.redirectUrl);
                  }
                }
              }
            );
          })
          .fail(function(xhr, textStatus, err) {
            self.showMessage("error", xhr.content, $.i18n("Error"));
            //self.warn("ERROR: code="+resp.error.code+", "+resp.error.message);
            self.$form.unblock();
            self.$progressbar.hide();
          });
      } else {
        self.showMessage("error", $.i18n("There was a validation error"));
        self.$form.unblock();
        self.$progressbar.hide();
      }

      return false;
    });
  };

  PdfExport.prototype.validate = function(params) {
    var self = this, isValid = true;

    // required
    self.$form.find(".required").each(function() {
      var $this = $(this);

      if ($this.val() === '') {
        $this.addClass("error");
        isValid = false;
      }
    });

    if (!params.Topic) {
      isValid = false;
    }

    return isValid;
  };

  PdfExport.prototype.serializeForm = function() {
    var self = this, params = {};

    $.each(self.$form.serializeArray(), function(index, item) {
      if (item.value !== '') {
        params[item.name] = item.value;
      }
    });

    return params;
  };

  // display a message
  PdfExport.prototype.showMessage = function(type, msg, title) {
    var self = this,
        selector = (type === 'error' ? '.foswikiErrorMessage' : '.foswikiSuccessMessage');

    self.$elem.find(selector).show().html((title?title+": ":"")+msg);
  };


  // hide message boxes and any flags
  PdfExport.prototype.hideMessages = function() {
    var self = this;

    self.$progressbar.hide();
    self.$elem.find('.foswikiErrorMessage').text("").hide();
    self.$elem.find('.foswikiSuccessMessage').text("").hide();
    self.$elem.find('.error').removeClass("error");
  };

  // A plugin wrapper around the constructor, 
  $.fn.pdfExport = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, "PdfExport")) { 
        $.data(this, "PdfExport", new PdfExport(this, opts)); 
      } 
    }); 
  };

  // Enable declarative widget instanziation 
  $(function() {
    $(".jqPdfExport:not(.jqPdfExportInited)").livequery(function() {
      $(this).addClass("jqPdfExportInited").pdfExport();
    });
  });

})(jQuery);
