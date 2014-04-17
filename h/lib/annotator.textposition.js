// Generated by CoffeeScript 1.6.3
/*
** Annotator 1.2.6-dev-bd83931
** https://github.com/okfn/annotator/
**
** Copyright 2012 Aron Carroll, Rufus Pollock, and Nick Stenning.
** Dual licensed under the MIT and GPLv3 licenses.
** https://github.com/okfn/annotator/blob/master/LICENSE
**
** Built at: 2014-04-17 01:24:51Z
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

  Annotator.Plugin.TextPosition = (function(_super) {
    __extends(TextPosition, _super);

    function TextPosition() {
      this._verifyPositionAnchor = __bind(this._verifyPositionAnchor, this);
      this._createAnchorFromTextPositionSelector = __bind(this._createAnchorFromTextPositionSelector, this);
      this._createTextPositionSelectorFromRange = __bind(this._createTextPositionSelectorFromRange, this);
      _ref = TextPosition.__super__.constructor.apply(this, arguments);
      return _ref;
    }

    TextPosition.prototype.pluginInit = function() {
      this.Annotator = Annotator;
      this.$ = Annotator.$;
      if (!this.annotator.plugins.EnhancedAnchoring) {
        throw new Error("The TextPosition Annotator plugin requires the EnhancedAnchoring plugin.");
      }
      if (!this.annotator.plugins.DomTextMapper) {
        throw new Error("The TextPosition Annotator plugin requires the DomTextMapper plugin.");
      }
      this.annotator.registerSelectorCreator({
        name: "TextPosition",
        describe: this._createTextPositionSelectorFromRange
      });
      return this.annotator.registerAnchoringStrategy({
        name: "position",
        priority: 50,
        create: this._createAnchorFromTextPositionSelector,
        verify: this._verifyPositionAnchor
      });
    };

    TextPosition.prototype._createTextPositionSelectorFromRange = function(selection) {
      var dfd, endOffset, startOffset, state;
      dfd = this.$.Deferred();
      if (selection.type !== "text range") {
        dfd.reject("I can only describe text ranges");
        return dfd.promise();
      }
      state = selection.data.dtmState;
      startOffset = (state.getStartInfoForNode(selection.range.start)).start;
      endOffset = (state.getEndInfoForNode(selection.range.end)).end;
      dfd.resolve([
        {
          type: "TextPositionSelector",
          start: startOffset,
          end: endOffset
        }
      ]);
      return dfd.promise();
    };

    TextPosition.prototype._createAnchorFromTextPositionSelector = function(target) {
      var dfd, selector,
        _this = this;
      dfd = this.$.Deferred();
      if (!this.annotator.plugins.DomTextMapper) {
        dfd.reject("DTM is not present");
        return dfd.promise();
      }
      selector = this.annotator.findSelector(target.selector, "TextPositionSelector");
      if (!selector) {
        dfd.reject("no TextPositionSelector found", true);
        return dfd.promise();
      }
      this.annotator.domMapper.prepare("anchoring").then(function(s) {
        var content, currentQuote, savedQuote, _base;
        content = s.getCorpus().slice(selector.start, selector.end).trim();
        currentQuote = _this.annotator.normalizeString(content);
        savedQuote = typeof (_base = _this.annotator).getQuoteForTarget === "function" ? _base.getQuoteForTarget(target) : void 0;
        if ((savedQuote != null) && currentQuote !== savedQuote) {
          dfd.reject("the saved quote doesn't match");
          return dfd.promise();
        }
        return dfd.resolve({
          type: "text position",
          start: selector.start,
          end: selector.end,
          startPage: s.getPageIndexForPos(selector.start),
          endPage: s.getPageIndexForPos(selector.end),
          quote: currentQuote
        });
      });
      return dfd.promise();
    };

    TextPosition.prototype._verifyPositionAnchor = function(anchor, reason, data) {
      var dfd,
        _this = this;
      dfd = this.$.Deferred();
      if (reason !== "corpus change") {
        dfd.resolve(true);
        return dfd.promise();
      }
      this.annotator.domMapper.prepare("verifying an anchor").then(function(s) {
        var content, corpus, currentQuote;
        corpus = s.getCorpus();
        content = corpus.slice(anchor.start, anchor.end).trim();
        currentQuote = _this.annotator.normalizeString(content);
        return dfd.resolve(currentQuote === anchor.quote);
      });
      return dfd.promise();
    };

    return TextPosition;

  })(Annotator.Plugin);

}).call(this);

//
//@ sourceMappingURL=annotator.textposition.map