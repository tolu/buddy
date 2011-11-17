# TODO: protect against source folder as out target during watch routine
# TODO: add version checking if present in config

fs = require 'fs'
path = require 'path'
coffee = require 'coffee-script'
stylus = require 'stylus'
# less = require 'less'
uglify = require 'uglify-js'
_ = require 'underscore'
growl = require 'growl'
{log, trace} = console
target = require './target'
file = require './file'
term = require './terminal'

CONFIG = 'build.json'

module.exports = class Builder
	JS: 'js'
	CSS: 'css'
	RE_JS_SRC_EXT: /\.coffee|\.js$/
	RE_CSS_SRC_EXT: /\.styl|\.less$/
	RE_IGNORE_FILE: /^[_|\.]|[-|\.]min\./
	RE_BUILT_HEADER: /^\/\*BUILT/g
	
	constructor: ->
		@config = null
		@base = null
		@jsSources =
			locations: []
			byPath: {}
			byModule: {}
			count: 0
		@cssSources =
			locations: []
			byPath: {}
			count: 0
		@jsTargets = []
		@cssTargets = []
	
	initialize: (configpath) ->
		unless @initialized
			# Load configuration file
			if @_loadConfig(configpath)
				for type in [@JS, @CSS]
					if @_validBuildType type
						# Generate source cache
						@_parseSourceFolder(path.resolve(@base, source), null, @[type + 'Sources']) for source in @config[type].sources
						# Generate build targets
						for item in @config[type].targets
							if target = @_targetFactory(item.in, item.out, type)
								@[type + 'Targets'].push target
		@initialized = true
		return @
	
	compile: (compress, bare) ->
		for type in [@JS, @CSS]
			if @[type + 'Targets'].length
				target.run(compress, bare) for target in @[type + 'Targets']
	
	watch: (compress, bare) ->
		return unless fs.watch
		@compile compress, bare
		for type in [@JS, @CSS]
			if @[type + 'Sources'].count
				term.out "watching for changes in #{term.colour('['+@config[type].sources.join(', ')+']', term.GREY)}...", 2
				@_watchFile(file, compress, bare) for path, file of @[type + 'Sources'].byPath
	
	deploy: ->
		@compile()
	
	_loadConfig: (configpath) ->
		if configpath
			# Check that the supplied path is valid
			configpath = path.resolve configpath
			if exists = path.existsSync(configpath)
				# Try default file name if directory
				if fs.statSync(configpath).isDirectory()
					configpath = path.join(configpath, CONFIG)
					exists = path.existsSync(configpath)
			unless exists
				term.out "#{term.colour('error', term.RED)} #{term.colour(path.basename(configpath), term.GREY)} not found in #{term.colour(path.dirname(configpath), term.GREY)}", 2
				return false
		else
			# Find the first instance of a CONFIG file based on the current working directory.
			while true
				dir = if dir? then path.resolve(dir, '../') else process.cwd()
				configpath = path.join(dir, CONFIG)
				break if path.existsSync(configpath)
				# Exit if we reach the volume root without finding our file
				if dir is '/'
					term.out "#{term.colour('error', term.RED)} #{term.colour(CONFIG, term.GREY)} not found on this path", 2
					return false
		
		# Read and parse config settings
		term.out "loading config #{term.colour(configpath, term.GREY)}", 2
		try
			@config = JSON.parse(fs.readFileSync(configpath, 'utf8'))
		catch e
			term.out "#{term.colour('error', term.RED)} error parsing #{term.colour(configpath, term.GREY)}", 2
			return false
		
		# Store the base directory
		@base = path.dirname configpath
		
		return true
	
	_validBuildType: (type) ->
			@config[type] and @config[type].sources and @config[type].sources.length and @config[type].targets and @config[type].targets.length
	
	_parseSourceFolder: (dir, root, cache) ->
		if root is null
			# Store root directory for File module package resolution
			root = dir
			cache.locations.push dir
		for item in fs.readdirSync dir
			# Skip ignored files
			unless item.match @RE_IGNORE_FILE
				itempath = path.resolve dir, item
				# Recurse child directory
				@_parseSourceFolder(itempath, root, cache) if fs.statSync(itempath).isDirectory()
				
				# Store File objects in cache
				if f = @_fileFactory(itempath, root)
					cache.byPath[f.filepath] = f
					cache.byModule[f.module] = f if f.module?
					cache.count++
	
	_fileFactory: (filepath, base) ->
		# Create JS file instance
		if filepath.match @RE_JS_SRC_EXT
			# Skip compiled files
			contents = fs.readFileSync(filepath, 'utf8')
			return null if contents.match @RE_BUILT_HEADER
			# Create and store File object
			return new file.JSFile filepath, base, contents
			
		# Create CSS file instance
		else if filepath.match @RE_CSS_SRC_EXT
			return new file.CSSFile filepath, base
		
		else return null
	
	_targetFactory: (input, output, type) ->
		inputpath = path.resolve @base, input
		outputpath = path.resolve @base, output
		# Check that the input exists
		unless path.existsSync(inputpath)
			term.out "#{term.colour('error', term.RED)} #{term.colour(input, term.GREY)} not found", 2
			return null
		# Check that input is included in sources
		for location in @[type + 'Sources'].locations
			dir = if fs.statSync(inputpath).isDirectory() then inputpath else path.dirname(inputpath)
			inSources = dir.indexOf(location) >= 0
			break if inSources
		# Abort if input isn't in sources
		unless inSources
			term.out "#{term.colour('error', term.RED)} #{term.colour(input, term.GREY)} not found in source path", 2
			return null
		# Abort if input is directory and output is file
		if fs.statSync(inputpath).isDirectory() and path.extname(outputpath).length
			term.out "#{term.colour('error', term.RED)} a file (#{term.colour(output, term.GREY)}) is not a valid output target for a directory (#{term.colour(input, term.GREY)}) input target", 2
			return null
		return new target[type.toUpperCase() + 'Target'] inputpath, outputpath, @[type + 'Sources']
	
	_watchFile: (file, compress, bare) ->
		# Store initial time and size
		stat = fs.statSync file.filepath
		file.lastChange = +stat.mtime
		file.lastSize = stat.size
		watcher = fs.watch file.filepath, callback = (event) =>
			# Clear old and create new on rename
			# if event is 'rename'
			# 	watcher.close()
			# 	try	 # if source no longer exists, never mind
			# 		watcher = fs.watch file.filepath, callback
			if event is 'change'
				# Compare time and size
				nstat = fs.statSync file.filepath
				last = +nstat.mtime
				size = nstat.size
				if size isnt file.lastSize and last isnt file.lastChange
					# Store new time and size
					file.lastChange = last
					file.lastSize = size
					term.out "[#{new Date().toLocaleTimeString()}] change detected in #{term.colour(file.filename, term.GREY)}", 0
					# Update contents
					file.updateContents(fs.readFileSync(file.filepath, 'utf8'))
					@compile(compress, bare)
	