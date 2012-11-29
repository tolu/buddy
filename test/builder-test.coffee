path = require('path')
fs = require('fs')
rimraf = require('rimraf')
should = require('should')
Builder = require('../lib/builder')
configuration = require('../lib/core/configuration')
processors = require('../lib/processors')
notify = require('../lib/utils/notify')

notify.silent = true

gatherFiles = (dir, files) ->
	files ||= []
	for item in fs.readdirSync(dir)
		p = path.resolve(dir, item)
		if fs.statSync(p).isFile()
			files.push(p)
		else
			gatherFiles(p, files)
	files

describe 'Builder', ->

	describe 'validating build type', ->
		before ->
			process.chdir(path.resolve(__dirname, 'fixtures/builder/validation'))
			@builder = new Builder()
		describe 'with valid source, source length, target, and target length', ->
			it 'should return true', ->
				config = require(path.resolve('buddy.js'))
				@builder._validBuildType(config.build.js).should.be.true
		describe 'without source', ->
			it 'should return false', ->
				config = require(path.resolve('buddy_invalid_source.js'))
				@builder._validBuildType(config.build.js).should.be.false
		describe 'without source length', ->
			it 'should return false', ->
				config = require(path.resolve('buddy_invalid_source_length.js'))
				@builder._validBuildType(config.build.js).should.be.false
		describe 'without target', ->
			it 'should return false', ->
				config = require(path.resolve('buddy_invalid_target.js'))
				@builder._validBuildType(config.build.js).should.be.false
		describe 'without target length', ->
			it 'should return false', ->
				config = require(path.resolve('buddy_invalid_target_length.js'))
				@builder._validBuildType(config.build.js).should.be.false

	describe 'parsing build target', ->
		before ->
			process.chdir(path.resolve(__dirname, 'fixtures/builder/init'))
			@builder = new Builder()
			@builder.sources.js = {locations:[path.resolve('target')]}
		it 'should return an error for an input file that doesn`t exist', (done) ->
			@builder._parseTargets 'js', [{'input': 'none.coffee', 'output': ''}], (err, instances) ->
				should.exist(err)
				done()
		it 'should return an error for an input file that doesn`t exist in sources', (done) ->
			@builder._parseTargets 'js', [{'input': '../source/src/main.coffee', 'output': ''}], (err, instances) ->
				should.exist(err)
				done()
		it 'should return an error for an input directory and an output file', (done) ->
			@builder._parseTargets 'js', [{'input': 'class', 'output': 'js/main.js'}], (err, instances) ->
				should.exist(err)
				done()
		it 'should result in a target count of 1 for a valid input file and output file', (done) ->
			@builder._parseTargets 'js', [{'input': 'target/main.coffee', 'output': 'main.js'}], (err, instances) ->
				instances.should.have.length(1)
				done()
		it 'should result in a target count of 2 with a valid target containing a valid child target', (done) ->
			@builder._parseTargets 'js', [{'input': 'target/main.coffee', 'output': 'main.js', 'targets':[{'input':'target/class', 'output':'../js'}]}], (err, instances) ->
				instances.should.have.length(2)
				done()

	# describe 'getting file type', ->
	# 	before ->
	# 		process.chdir(path.resolve(__dirname, 'fixtures/builder/init'))
	# 	beforeEach ->
	# 		@builder = new Builder()
	# 		config = @builder.config = new Configuration()
	# 		@builder.plugins = plugins.load()
	# 	it 'should return "js" for a js file', ->
	# 		@builder._getFileType('here/is/somefile.js').should.eql('js')
	# 	it 'should return "js" for a coffee file', ->
	# 		@builder._getFileType('here/is/somefile.coffee').should.eql('js')
	# 	it 'should return "css" for a css file', ->
	# 		@builder._getFileType('here/is/somefile.css').should.eql('css')
	# 	it 'should return "css" for a stylus file', ->
	# 		@builder._getFileType('here/is/somefile.styl').should.eql('css')
	# 	it 'should return "css" for a less file', ->
	# 		@builder._getFileType('here/is/somefile.less').should.eql('css')

	describe.skip 'build', ->
		beforeEach ->
			@builder = new Builder
		afterEach (done) ->
			@builder = null
			rimraf path.resolve(process.cwd(), 'output'), (err) ->
				done()
		describe 'file target', ->
			before ->
				process.chdir(path.resolve(__dirname, 'fixtures/builder/build/project'))
			describe 'with a single coffee file', ->
				it 'should build 1 js file', ->
					@builder.initialize('buddy_single-file.js')
					@builder.build()
					fs.existsSync(@builder.jsTargets[0].output).should.be.true
			describe 'with a single coffee file requiring 1 dependency', ->
				beforeEach ->
					@builder.initialize('buddy_single-file-with-dependency.js')
					@builder.build()
				it 'should build 1 js file', ->
					fs.existsSync(@builder.jsTargets[0].output).should.be.true
				it 'should contain 2 modules', ->
					contents = fs.readFileSync(@builder.jsTargets[0].output, 'utf8')
					contents.should.include("require.register('package/class'")
					contents.should.include("require.register('package/classcamelcase'")
			describe 'with a single coffee file containing a module wrapper', ->
				beforeEach ->
					@builder = new Builder
					@builder.initialize('buddy_single-file-with-wrapper.js')
					@builder.build()
				it 'should build 1 js file containing only 1 module wrapper', ->
					fs.existsSync(@builder.jsTargets[0].output).should.be.true
			describe 'with a single stylus file', ->
				it 'should build 1 css file', ->
					@builder.initialize('buddy_single-styl-file.js')
					@builder.build()
					fs.existsSync(@builder.cssTargets[0].output).should.be.true
			describe 'with a single less file', ->
				it 'should build 1 css file', ->
					@builder.initialize('buddy_single-less-file.js')
					@builder.build()
					fs.existsSync(@builder.cssTargets[0].output).should.be.true
		describe 'directory target', ->
			before ->
				process.chdir(path.resolve(__dirname, 'fixtures/builder/build/library'))
			describe 'with 3 coffee files', ->
				it 'should build 3 js files', ->
					@builder.initialize('buddy.js')
					@builder.build()
					gatherFiles(@builder.jsTargets[0].output).should.have.length(3)
			describe 'with 3 coffee files and the "moldular" flag set to false', ->
				it 'should build 3 js files without module wrappers', ->
					@builder.initialize('buddy-nodejs.js')
					@builder.build()
					files = gatherFiles(@builder.jsTargets[0].output)
					for f in files
						fs.readFileSync(f, 'utf8').should.not.include('require.register(')
			describe 'with 2 stylus files', ->
				it 'should build 2 css files', ->
					@builder.initialize('buddy_styl.js')
					@builder.build()
					gatherFiles(@builder.cssTargets[0].output).should.have.length(2)
		describe 'project', ->
			before ->
				process.chdir(path.resolve(__dirname, 'fixtures/builder/build/project'))
			describe 'with a single coffee file and a stylus directory', ->
				beforeEach ->
					@builder.initialize('buddy.js')
					@builder.build()
				it 'should build 1 concatenated js file', ->
					fs.existsSync(@builder.jsTargets[0].output).should.be.true
				it 'should build 2 css files', ->
					gatherFiles(@builder.cssTargets[0].output).should.have.length(2)
		describe 'complex project', ->
			before ->
				process.chdir(path.resolve(__dirname, 'fixtures/builder/build/project-complex'))
			describe 'with 2 js targets and 1 child target sharing assets', ->
				beforeEach ->
					@builder.initialize('buddy.js')
					@builder.build()
				it 'should build 3 concatenated js files', ->
					gatherFiles(path.resolve(process.cwd(), 'output')).should.have.length(3)
				it 'should build a child js file without require.js source', ->
					contents = fs.readFileSync(path.resolve(process.cwd(), 'output/section.js'), 'utf8')
					contents.should.not.include('require = function(path)')
				it 'should build a child js file without source shared with it`s parent', ->
					contents = fs.readFileSync(path.resolve(process.cwd(), 'output/section.js'), 'utf8')
					contents.should.not.include("require.module('utils/util',")
				it 'should build a child js file that is different than the same file built without a parent target', ->
					fs.readFileSync(path.resolve(process.cwd(), 'output/section.js'), 'utf8').should.not.eql(fs.readFileSync(path.resolve(process.cwd(), 'output/section/someSection.js'), 'utf8'))
		describe 'js project', ->
			before ->
				process.chdir(path.resolve(__dirname, 'fixtures/builder/build/project-js'))
			describe 'with a single js file requiring 1 dependency', ->
				beforeEach ->
					@builder.initialize('buddy.js')
					@builder.build()
				it 'should build 1 js file', ->
					fs.existsSync(@builder.jsTargets[0].output).should.be.true
				it 'should contain 2 modules', ->
					contents = fs.readFileSync(@builder.jsTargets[0].output, 'utf8')
					contents.should.include("require.register('main'")
					contents.should.include("require.register('package/classcamelcase'")
			describe 'with a single js file requiring 1 wrapped dependency', ->
				beforeEach ->
					@builder.initialize('buddy_wrapped.js')
					@builder.build()
				it 'should build 1 js file', ->
					fs.existsSync(@builder.jsTargets[0].output).should.be.true
				it 'should contain 2 modules', ->
					contents = fs.readFileSync(@builder.jsTargets[0].output, 'utf8')
					contents.should.include("require.register('mainwrapped'")
					contents.should.include("require.register('package/prewrapped'")
			describe 'with a directory of empty js files', ->
				it 'should build 2 js files', ->
					@builder.initialize('buddy_empty.js')
					@builder.build()
					gatherFiles(@builder.jsTargets[0].output).should.have.length(2)
