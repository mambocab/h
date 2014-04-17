// Generated by CoffeeScript 1.6.3
/*
** Annotator 1.2.6-dev-bd83931
** https://github.com/okfn/annotator/
**
** Copyright 2012 Aron Carroll, Rufus Pollock, and Nick Stenning.
** Dual licensed under the MIT and GPLv3 licenses.
** https://github.com/okfn/annotator/blob/master/LICENSE
**
** Built at: 2014-04-17 01:25:37Z
*/



/*
//
*/

// Generated by CoffeeScript 1.6.3
(function() {
  var _ref,
    __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; },
    __hasProp = {}.hasOwnProperty,
    __extends = function(child, parent) { for (var key in parent) { if (__hasProp.call(parent, key)) child[key] = parent[key]; } function ctor() { this.constructor = child; } ctor.prototype = parent.prototype; child.prototype = new ctor(); child.__super__ = parent.prototype; return child; };

  Annotator.Plugin.TextQuote = (function(_super) {
    __extends(TextQuote, _super);

    function TextQuote() {
      this._createTextQuoteSelectorFromRange = __bind(this._createTextQuoteSelectorFromRange, this);
      _ref = TextQuote.__super__.constructor.apply(this, arguments);
      return _ref;
    }

    TextQuote.prototype.pluginInit = function() {
      var _this = this;
      if (!this.annotator.plugins.EnhancedAnchoring) {
        throw new Error("The TextQuote Annotator plugin requires the EnhancedAnchoring plugin.");
      }
      this.$ = Annotator.$;
      this.annotator.registerSelectorCreator({
        name: "TextQuote",
        describe: this._createTextQuoteSelectorFromRange
      });
      return this.annotator.getQuoteForTarget = function(target) {
        var selector;
        selector = _this.annotator.findSelector(target.selector, "TextQuoteSelector");
        if (selector != null) {
          return _this.annotator.normalizeString(selector.exact);
        } else {
          return null;
        }
      };
    };

    TextQuote.prototype._createTextQuoteSelectorFromRange = function(selection) {
      var dfd, endOffset, prefix, quote, rangeEnd, rangeStart, startOffset, state, suffix, _ref1;
      dfd = this.$.Deferred();
      if (selection.type !== "text range") {
        dfd.reject("I can only describe text ranges");
        return dfd.promise();
      }
      if (selection.range == null) {
        throw new Error("Called getTextQuoteSelector(range) with null range!");
      }
      rangeStart = selection.range.start;
      if (rangeStart == null) {
        throw new Error("Called getTextQuoteSelector(range) on a range with no valid start.");
      }
      rangeEnd = selection.range.end;
      if (rangeEnd == null) {
        throw new Error("Called getTextQuoteSelector(range) on a range with no valid end.");
      }
      dfd.resolve([
        this.annotator.plugins.DomTextMapper ? (state = selection.data.dtmState, startOffset = (state.getStartInfoForNode(rangeStart)).start, endOffset = (state.getEndInfoForNode(rangeEnd)).end, quote = state.getCorpus().slice(startOffset, endOffset).trim(), (_ref1 = state.getContextForCharRange(startOffset, endOffset), prefix = _ref1[0], suffix = _ref1[1], _ref1), {
          type: "TextQuoteSelector",
          prefix: prefix,
          exact: quote,
          suffix: suffix
        }) : {
          type: "TextQuoteSelector",
          exact: this.annotator.normalizeString(selection.range.text().trim())
        }
      ]);
      return dfd.promise();
    };

    return TextQuote;

  })(Annotator.Plugin);

}).call(this);

//
//@ sourceMappingURL=annotator.textquote.map