var Builder, CONFIG, coffee, file, fs, growl, log, path, stylus, target, term, trace, uglify, _;

fs = require('fs');

path = require('path');

coffee = require('coffee-script');

stylus = require('stylus');

uglify = require('uglify-js');

_ = require('underscore');

growl = require('growl');

log = console.log, trace = console.trace;

target = require('./target');

file = require('./file');

term = require('./terminal');

CONFIG = 'build.json';

module.exports = Builder = (function() {

  Builder.prototype.JS = 'js';

  Builder.prototype.CSS = 'css';

  Builder.prototype.RE_JS_SRC_EXT = /\.coffee|\.js$/;

  Builder.prototype.RE_CSS_SRC_EXT = /\.styl|\.less$/;

  Builder.prototype.RE_IGNORE_FILE = /^[_|\.]|[-|\.]min\./;

  Builder.prototype.RE_BUILT_HEADER = /^\/\*BUILT/g;

  function Builder() {
    this.config = null;
    this.base = null;
    this.jsSources = {
      locations: [],
      byPath: {},
      byModule: {},
      count: 0
    };
    this.cssSources = {
      locations: [],
      byPath: {},
      count: 0
    };
    this.jsTargets = [];
    this.cssTargets = [];
  }

  Builder.prototype.initialize = function(configpath) {
    var item, source, type, _i, _j, _k, _len, _len2, _len3, _ref, _ref2, _ref3;
    if (!this.initialized) {
      if (this._loadConfig(configpath)) {
        _ref = [this.JS, this.CSS];
        for (_i = 0, _len = _ref.length; _i < _len; _i++) {
          type = _ref[_i];
          if (this._validBuildType(type)) {
            _ref2 = this.config[type].sources;
            for (_j = 0, _len2 = _ref2.length; _j < _len2; _j++) {
              source = _ref2[_j];
              this._parseSourceFolder(path.resolve(this.base, source), null, this[type + 'Sources']);
            }
            _ref3 = this.config[type].targets;
            for (_k = 0, _len3 = _ref3.length; _k < _len3; _k++) {
              item = _ref3[_k];
              if (target = this._targetFactory(item["in"], item.out, type)) {
                this[type + 'Targets'].push(target);
              }
            }
          }
        }
      }
    }
    this.initialized = true;
    return this;
  };

  Builder.prototype.compile = function(compress, bare) {
    var target, type, _i, _len, _ref, _results;
    _ref = [this.JS, this.CSS];
    _results = [];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      type = _ref[_i];
      if (this[type + 'Targets'].length) {
        _results.push((function() {
          var _j, _len2, _ref2, _results2;
          _ref2 = this[type + 'Targets'];
          _results2 = [];
          for (_j = 0, _len2 = _ref2.length; _j < _len2; _j++) {
            target = _ref2[_j];
            _results2.push(target.run(compress, bare));
          }
          return _results2;
        }).call(this));
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  };

  Builder.prototype.watch = function(compress, bare) {
    var file, path, type, _i, _len, _ref, _results;
    if (!fs.watch) return;
    this.compile(compress, bare);
    _ref = [this.JS, this.CSS];
    _results = [];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      type = _ref[_i];
      if (this[type + 'Sources'].count) {
        term.out("watching for changes in " + (term.colour('[' + this.config[type].sources.join(', ') + ']', term.GREY)) + "...", 2);
        _results.push((function() {
          var _ref2, _results2;
          _ref2 = this[type + 'Sources'].byPath;
          _results2 = [];
          for (path in _ref2) {
            file = _ref2[path];
            _results2.push(this._watchFile(file, compress, bare));
          }
          return _results2;
        }).call(this));
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  };

  Builder.prototype.deploy = function() {
    return this.compile();
  };

  Builder.prototype._loadConfig = function(configpath) {
    var dir, exists;
    if (configpath) {
      configpath = path.resolve(configpath);
      if (exists = path.existsSync(configpath)) {
        if (fs.statSync(configpath).isDirectory()) {
          configpath = path.join(configpath, CONFIG);
          exists = path.existsSync(configpath);
        }
      }
      if (!exists) {
        term.out("" + (term.colour('error', term.RED)) + " " + (term.colour(path.basename(configpath), term.GREY)) + " not found in " + (term.colour(path.dirname(configpath), term.GREY)), 2);
        return false;
      }
    } else {
      while (true) {
        dir = dir != null ? path.resolve(dir, '../') : process.cwd();
        configpath = path.join(dir, CONFIG);
        if (path.existsSync(configpath)) break;
        if (dir === '/') {
          term.out("" + (term.colour('error', term.RED)) + " " + (term.colour(CONFIG, term.GREY)) + " not found on this path", 2);
          return false;
        }
      }
    }
    term.out("loading config " + (term.colour(configpath, term.GREY)), 2);
    try {
      this.config = JSON.parse(fs.readFileSync(configpath, 'utf8'));
    } catch (e) {
      term.out("" + (term.colour('error', term.RED)) + " error parsing " + (term.colour(configpath, term.GREY)), 2);
      return false;
    }
    this.base = path.dirname(configpath);
    return true;
  };

  Builder.prototype._validBuildType = function(type) {
    return this.config[type] && this.config[type].sources && this.config[type].sources.length && this.config[type].targets && this.config[type].targets.length;
  };

  Builder.prototype._parseSourceFolder = function(dir, root, cache) {
    var f, item, itempath, _i, _len, _ref, _results;
    if (root === null) {
      root = dir;
      cache.locations.push(dir);
    }
    _ref = fs.readdirSync(dir);
    _results = [];
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      item = _ref[_i];
      if (!item.match(this.RE_IGNORE_FILE)) {
        itempath = path.resolve(dir, item);
        if (fs.statSync(itempath).isDirectory()) {
          this._parseSourceFolder(itempath, root, cache);
        }
        if (f = this._fileFactory(itempath, root)) {
          cache.byPath[f.filepath] = f;
          if (f.module != null) cache.byModule[f.module] = f;
          _results.push(cache.count++);
        } else {
          _results.push(void 0);
        }
      } else {
        _results.push(void 0);
      }
    }
    return _results;
  };

  Builder.prototype._fileFactory = function(filepath, base) {
    var contents;
    if (filepath.match(this.RE_JS_SRC_EXT)) {
      contents = fs.readFileSync(filepath, 'utf8');
      if (contents.match(this.RE_BUILT_HEADER)) return null;
      return new file.JSFile(filepath, base, contents);
    } else if (filepath.match(this.RE_CSS_SRC_EXT)) {
      return new file.CSSFile(filepath, base);
    } else {
      return null;
    }
  };

  Builder.prototype._targetFactory = function(input, output, type) {
    var dir, inSources, inputpath, location, outputpath, _i, _len, _ref;
    inputpath = path.resolve(this.base, input);
    outputpath = path.resolve(this.base, output);
    if (!path.existsSync(inputpath)) {
      term.out("" + (term.colour('error', term.RED)) + " " + (term.colour(input, term.GREY)) + " not found", 2);
      return null;
    }
    _ref = this[type + 'Sources'].locations;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      location = _ref[_i];
      dir = fs.statSync(inputpath).isDirectory() ? inputpath : path.dirname(inputpath);
      inSources = dir.indexOf(location) >= 0;
      if (inSources) break;
    }
    if (!inSources) {
      term.out("" + (term.colour('error', term.RED)) + " " + (term.colour(input, term.GREY)) + " not found in source path", 2);
      return null;
    }
    if (fs.statSync(inputpath).isDirectory() && path.extname(outputpath).length) {
      term.out("" + (term.colour('error', term.RED)) + " a file (" + (term.colour(output, term.GREY)) + ") is not a valid output target for a directory (" + (term.colour(input, term.GREY)) + ") input target", 2);
      return null;
    }
    return new target[type.toUpperCase() + 'Target'](inputpath, outputpath, this[type + 'Sources']);
  };

  Builder.prototype._watchFile = function(file, compress, bare) {
    var callback, stat, watcher;
    var _this = this;
    stat = fs.statSync(file.filepath);
    file.lastChange = +stat.mtime;
    file.lastSize = stat.size;
    return watcher = fs.watch(file.filepath, callback = function(event) {
      var last, nstat, size;
      if (event === 'change') {
        nstat = fs.statSync(file.filepath);
        last = +nstat.mtime;
        size = nstat.size;
        if (size !== file.lastSize && last !== file.lastChange) {
          file.lastChange = last;
          file.lastSize = size;
          term.out("[" + (new Date().toLocaleTimeString()) + "] change detected in " + (term.colour(file.filename, term.GREY)), 0);
          file.updateContents(fs.readFileSync(file.filepath, 'utf8'));
          return _this.compile(compress, bare);
        }
      }
    });
  };

  return Builder;

})();