'use strict';

const uglify = require('uglify-js');

const RE_LICENSE = /@preserve|@license|@cc_on/i;
const DEFAULT_OPTIONS = {
  output: {
    // Preserve special multiline comments
    comments: RE_LICENSE
  },
  compress: {
    // Don't remove wrapping brackets
    negate_iife: false
  },
  fromString: true
};

module.exports = {
  name: 'uglify',
  type: 'js',

  /**
   * Register plugin
   * @param {Config} config
   */
  register (config) {
    config.extendFileDefinitionForExtensionsOrType(extend, null, this.type);
  }
};

/**
 * Extend 'prototype' with new behaviour
 * @param {Object} prototype
 * @param {Object} utils
 */
function extend (prototype, utils) {
  const { debug, strong } = utils.cnsl;

  /**
   * Compress file contents
   * @param {Object} buildOptions
   *  - {Boolean} bootstrap
   *  - {Boolean} boilerplate
   *  - {Boolean} browser
   *  - {Boolean} bundle
   *  - {Boolean} compress
   *  - {Array} ignoredFiles
   *  - {Boolean} helpers
   *  - {Boolean} watchOnly
   * @param {Function} fn(err)
   * @returns {null}
   */
  prototype.compress = function compress (buildOptions, fn) {
    try {
      const options = Object.assign({}, DEFAULT_OPTIONS, this.options.pluginOptions.uglify);
      const content = uglify.minify(this.content, options).code;

      debug(`compress: ${strong(this.relpath)}`, 4);
      this.content = content;
    } catch (err) {
      return fn(err);
    }
    fn();
  };
}