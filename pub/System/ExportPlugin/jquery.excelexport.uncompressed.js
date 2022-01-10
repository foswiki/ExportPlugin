/*
 * jQuery excel export plugin 1.0
 *
 * Copyright (c) 2020 Michael Daum http://michaeldaumconsulting.com
 *
 * Licensed under the GPL license http://www.gnu.org/licenses/gpl.html
 *
 */

"use strict";
(function($) {

  // Create the defaults once
  var defaults = {
        debug: false,
        form: ".jqExportForm",
        errorElem: ".jqExportErrorMessage",
        successElem: ".jqExportSuccessMessage",
      };


  // The actual plugin constructor 
  function ExcelExport(elem, opts) { 
    var self = this;

    self.$elem = $(elem); 
    self.opts = $.extend({}, defaults, opts, self.$elem.data()); 

    self.$form = $(self.opts.form);
    self.$errorElem = $(self.opts.errorElem);
    self.$successElem = $(self.opts.successElem);

    self.init(); 
  } 

  // logging
  ExcelExport.prototype.log = function() {
    var self = this, args;

    if (!console || !self.opts.debug) {
      return;
    }

    args = $.makeArray(arguments);
    args.unshift("EXCEL-EXPORT:");
    console.log.apply(console, args);
  };

  // warning
  ExcelExport.prototype.warn = function() {
    var self = this, args;

    if (!console) {
      return;
    }

    args = $.makeArray(arguments);
    args.unshift("EXCEL-EXPORT:");
    console.warn.apply(console, args);
  };

  // init form
  ExcelExport.prototype.init = function() {
    var self = this;

    // add submit handler
    self.$elem.on("click", function(e) {
      var params, origTopics;

      e.preventDefault();

      // Disable the submit button to prevent repeated clicks
      self.$form.block({message:''});
      self.hideMessages();

      params = self.serializeForm();

      if (self.validate(params)) {
        // submit valid form

        self.log("submitting to backend params=",params);
            
        $.jsonRpc(
          foswiki.getScriptUrlPath("jsonrpc"), {
            namespace: "ExportPlugin",
            method: "excel",
            params: params,
            error: function(resp, textStatus, xhr) {
              self.showMessage("error", resp.error.message, $.i18n("Error"));
              self.warn("ERROR: code="+resp.error.code+", "+resp.error.message);
              self.$form.unblock();
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

      } else {
        self.showMessage("error", $.i18n("There was a validation error"));
        self.$form.unblock();
      }

      return false;
    });
  };

  ExcelExport.prototype.validate = function(params) {
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

  ExcelExport.prototype.serializeForm = function() {
    var self = this, params = {};

    $.each(self.$form.serializeArray(), function(index, item) {
      if (item.value !== '') {
        params[item.name] = item.value;
      }
    });

    return params;
  };

  // display a message
  ExcelExport.prototype.showMessage = function(type, msg, title) {
    var self = this,
        elem = (type === 'error' ? self.$errorElem : self.$successElem);

    elem.show().html((title?title+": ":"")+msg);
  };


  // hide message boxes and any flags
  ExcelExport.prototype.hideMessages = function() {
    var self = this;

    self.$errorElem.text("").hide();
    self.$successElem.text("").hide();
    self.$form.find('.error').removeClass("error");
  };

  // A plugin wrapper around the constructor, 
  $.fn.excelExport = function (opts) { 
    return this.each(function () { 
      if (!$.data(this, "ExcelExport")) { 
        $.data(this, "ExcelExport", new ExcelExport(this, opts)); 
      } 
    }); 
  };

  // Enable declarative widget instanziation 
  $(function() {
    $(".jqExcelExport").livequery(function() {
      $(this).excelExport();
    });
  });

})(jQuery);
