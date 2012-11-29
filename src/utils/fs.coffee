fs = require('fs')
path = require('path')
mkdirp = require('mkdirp')
rimraf = require('rimraf')
# Node 0.8.0 api change
exports.existsSync = existsSync = fs.existsSync or path.existsSync
exports.exists = exists = fs.exists or path.exists

RE_IGNORE = /^[\.~]|~$/

#starts with '.', or '~', ends with '~'
exports.ignoredHidden = /^[\.~]|~$/
#starts with '.', or '~' contains '-min.', '.min.' or 'svn', ends with '~'
exports.ignored = /^[\.~]|[-\.]min[-\.]|svn|~$/

# Check that a 'filepath' is likely a child of a given directory
# Applies to nested directories
# Only makes String comparison. Does not check for existance
# @param {String} dir
# @param {String} file
# @returns {Boolean}
exports.indir = (dir, filepath) ->
	dir = path.resolve(dir)
	filepath = path.resolve(filepath)
	if filepath.indexOf(dir) isnt -1
		if path.relative(dir, filepath).indexOf('..') isnt -1
			return false
		else
			return true
	else
		return false

# Read and store the contents of a directory, ignoring files of type specified
# @param {String} dir
# @param {Regex} ignore
# @param {Function} fn(err, files)
exports.readdir = readdir = (dir, ignore, fn) ->
	# Merge ignores
	ignore = if ignore then new RegExp(exports.ignoredHidden.source + '|' + ignore.source) else exports.ignoredHidden
	_outstanding = 0
	_files = []
	_readdir = (dir) ->
		_outstanding++
		fs.readdir dir, (err, files) ->
			_outstanding--
			if err
				# Exit if proper error, otherwise skip
				return if err.code is 'ENOENT'
				else return fn(err)
			else
				files.forEach (file) ->
					# Skip ignored files
					unless ignore.test(path.basename(file))
						filepath = path.resolve(dir, file)
						_outstanding++
						fs.stat filepath, (err, stats) ->
							_outstanding--
							if err
								# Exit if proper error, otherwise skip
								return if err.code is 'ENOENT'
								else return fn(err)
							else
								# Recurse child directory
								if stats.isDirectory()
									_readdir(filepath)
								else
									# Store
									_files.push(filepath)
									# Return if no outstanding
									fn(null, _files) unless _outstanding
				# Return if no outstanding
				fn(null, _files) unless _outstanding
	_readdir(dir)

# Recursively create directory path specified by 'filepath'
# @param {String} filepath
# @param {Function} fn(err)
exports.mkdir = mkdir = (filepath, fn) ->
	# Resolve directory name if passed a file
	dir = if path.extname(filepath) then path.dirname(filepath) else filepath
	unless existsSync(dir)
		mkdirp dir, (err) ->
			if err then fn(err) else fn()
	else
		fn()

# Move file or directory 'source' to 'destination'
# @param {String} source
# @param {String} destination
# @param {Function} fn(err, filepath)
exports.mv = mv = (source, destination, fn) ->
	mkdir destination, (err) ->
		if err
			fn(err)
		else
			filepath = path.resolve(destination, path.basename(source))
			if existsSync(filepath)
				fn(new Error('already exists: ' + filepath))
			else
				fs.rename source, filepath, (err) ->
					if err then fn(err) else fn(null, filepath)

# Copy file or directory 'source' to 'destination'
# Copies contents of 'source' if directory and ends in trailing '/'
# @param {String} source
# @param {String} destination
# @param {Function} fn(err, filepath)
exports.cp = cp = (source, destination, fn) ->
	_outstanding = 0
	_base = ''
	_filepath = ''
	_first = true
	_cp = (source, destination) ->
		_outstanding++
		fs.stat source, (err, stats) ->
			_outstanding--
			if err
				# Exit if proper error, otherwise skip
				return if err.code is 'ENOENT'
				else return fn(err)
			else
				isDestFile = path.extname(destination).length
				# File
				if stats.isFile()
					# Handle file or directory as destination
					destDir = if isDestFile then path.dirname(destination) else destination
					destName = if isDestFile then path.basename(destination) else path.basename(source)
					filepath = path.resolve(destDir, destName)
					# Write file if it doesn't already exist
					if existsSync(filepath)
						fn(new Error('file already exists: ' + source))
					else
						_outstanding++
						# Return the new path for the first source
						if _first
							_filepath = filepath
							_first = false
						# Pipe stream
						fs.createReadStream(source).pipe(file = fs.createWriteStream(filepath))
						file.on 'error', (err) ->
							fn(err)
						file.on 'close', ->
							_outstanding--
							# Return if no outstanding
							fn(null, _filepath) unless _outstanding
				# Directory
				else
					# Guard against invalid directory to file copy
					if isDestFile
						fn(new Error('invalid destination for copy: ' + destination))
					else
						# Copy contents only if source ends in '/'
						contentsOnly = _first and /\\|\/$/.test(source)
						dest = if contentsOnly then destination else path.resolve(destination, path.basename(source))
						# Create in destination
						_outstanding++
						mkdir dest, (err) ->
							_outstanding--
							if err
								return fn(err)
							else
								# Loop through contents
								_outstanding++
								fs.readdir source, (err, files) ->
									_outstanding--
									if err
										# Exit if proper error, otherwise skip
										return if err.code is 'ENOENT'
										else return fn(err)
									else
										# Return the new path for the first source
										if _first
											_filepath = dest
											_first = false
										# Loop through files and cp
										files.forEach (file) ->
											_cp(path.resolve(source, file), dest)
										# Return if no outstanding
										fn(null, _filepath) unless _outstanding
		# Return if no outstanding
		fn(null, _filepath) unless _outstanding
	_cp(source, destination)

# Recursive remove file or directory
# Makes sure only project sources are removed
# @param {String} source
# @param {Function} fn(err)
exports.rm = rm = (source, fn) ->
	if existsSync(source)
		if source.indexOf(process.cwd()) isnt -1
			rimraf source, (err) ->
				if err then fn(err) else fn()
		else
			fn(new Error('cannot rm source outside of project path: ' + source))
	else
		fn(new Error('cannot rm non-existant source: ' + source))
