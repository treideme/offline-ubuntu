#!/usr/bin/ruby
#
# debpartial - Debian Packages/Sources file partition tool.
#
# Copyright (C) 2002  Masato Taruishi <taru@debian.org>
# Copyright (C) 2022  Thomas Reidemeister <thomas@labforge.ca>
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License with
#  the Debian GNU/Linux distribution in file /usr/share/common-licenses/GPL;
#  if not, write to the Free Software Foundation, Inc., 59 Temple Place,
#  Suite 330, Boston, MA  02111-1307  USA
#
=begin

== NAME

debpartial - Debian Packages/Sources file partition tool

== SYNOPSIS

debpartial [options] <source> <dest>

== DESCRIPTION

debpartial is a program to separate Packages.gz and Sources.gz files by
size of packages and sources. You can create partial debian archives
easily by using this program. For example, this is useful in the case of:

(1)creating 1 DVD/CD Debian (including binaries and sources).
(2)separating the debian archive into several harddisks.
(3)mirroring packages only you want (using debmirror etc).

== USAGE

 debpartial [--help] [--nosource] [--size=num[,num,..] ...]
  [--dist=foo[,bar,..] ...] [--section=foo[,bar,..] ...] 
  [--include=foo[,bar..] ...] [--include-from=foo]
  [--dirmap=foo[,bar,..] ...] [--limit=num] [--merge-source]
  [--arch=foo[,bar,..] ...] [--ignore-large-packages] <source> <dest> 

# where <source> is a top directory of debian archive (need
# only Packages.gz and/or Sources.gz) and <dest> is a top
# directory which the separated Packages.gz and/or 
# Sources.gz are located under.

== OPTIONS

* --help

  Print usage summary of this program.

* --nosource

  Don't handle source files.

* --size=num[,num..] ... -S 

  Specify the comma separated partition size list. May use absolute integer
  value and/or ((*MediaType*)). see ((*MEDIATYPE*)) Section for more
  info (Default: CD74).

* --srcsize=num[,num..] ... -R

  Specify the comma separated source partition size list. May use absolute
  integer value and/or MediaType. If this option is not given, then --size
  is also used for source patitions.

* --dist=foo[,bar,..] ...] -d

  Specify the comma separated distribution list to handle (Default: unstable).

* --section=foo[,bar,..] ...] -s

  Specify the comma separated section list to handle (Default: main,contrib,non-free).

* --arch=foo[,bar,..] ...] -a

  Specify the comma separatd arch list to handle (Default: i386).

* --include=foo[,bar..] ...] -i

  Specify the comma separated package list to handle. The packages
  listed in this option are treated earlier than one by --include-from.

* --include-from=file

  Specify the file which lists package names to handle. If this option
  is given, packages not listed in the file are excluded. Packages listed
  in the file are treated as in-order.

* --dirmap=foo[,bar,..] ...] -D

  Create the map from each patition to name (i.e. patition 0 will be named foo,
  and partition 1 will be named bar)
 (Default: <prefix>0,<prefix>1,<prefix>2,....)

* --dirprefix=foo

  Specify the prefix of all partition (Default: Debian).

* --dirsrcprefix=foo

  Specify the prefix of all src partition (Default: Debian-Src). If --merge-source
  is given, this arguments will be ignored.

* --limit=num -l

  Specify the maximum number of partitions. 0 means no-limit (Default: 0).

* --merge-source -m

  Merging source files and packages in the same partition.

* --ignore-large-packages -I

  Ignoring packages which are larger than partition size. If this option
  is not given, debpartial exits with error for a large package.

== MEDIATYPE

((*MediaType*)) is alias of an absolute integer value for a media
such as CD, DVD. For example, CD74 MediaType is an alias of the absolute
size of 74min CD. debpartial has the following built-in MediaTypes:

(1)FD      - 2HD 1.44M Floppy Disk
(1)CF8     - 8M Compact Flash
(1)CF16    - 16M Compact Flash
(1)CF32    - 32M Compact Flash
(1)CF64    - 64M Compact Flash
(2)MO128   - 128M MO
(3)MO230   - 230M MO
(4)MO640   - 640M MO
(6)CD74    - 74min (650M) CD
(7)CD80    - 80min (700M) CD
(5)MO1.3G  - 1.3G MO
(5)DVD-RAM - (2.6G) DVD-RAM
(8)DVD     - Single Layer (4.7G) DVD-ROM

Each absolute value is 93% of theoretical value because fixed cluster
(or block) size may make the space of written files grow up.
This calculation isn't a perfect solution, but mostly works.

== EXAMPLE

 debpartial --dist=unstable,testing --section=main --limit 1 \
  --size=400000000 --merge-source --arch=i386,sparc \
  /home/ftp/pub/debian/ /home/ftp/pub/debpartial/

== BUGS

(1)debpartial doesn't consider about disk cluster size and also the size of generated Packages/Sources.gz.

== AUTHOR

debpartial was written by Masato Taruishi.

=end

require 'getoptlong'
require 'tempfile'
require 'zlib'
require 'fileutils'

# Media name to maximum size map
#
# SAFE_SPACE is a rate for going down maximum size because fixed
# cluster (block) size may make the space of written files
# grow up.
#
# CD size is caluclated as follows:
#
#
#  74min CD -> ((74m * 60)s * 75) * 2048 (CD-ROM Mode 2, XA Form 1/CD-I)
#  80min CD -> (((79m * 60)s * 75)+(57s * 75) + 74
#                                 * 2048 (CD-ROM Mode 2, XA Form 1/CD-I)
#              (i.e 79m57s74)
#
# A Block can take up 1/75 sec. of audio data, i.e. on a 74 minute CD
# there are 74*60*75=333000 blocks.
#
#
SAFE_SPACE=0.93
SIZEMAP = {
  "FD" => 1440000, 
  "CF8" => 8 * 1024 * 1024,
  "CF16" => 16 * 1024 * 1024,
  "CF32" => 32 * 1024 * 1024,
  "CF64" => 64 * 1024 * 1024,
  "MO128" => 128 * 1024 * 1024,
  "MO230" => 230 * 1024 * 1024,
  "MO640" => 640 * 1024 * 1024,
  "MO1.3G" => 1300 * 1024 * 1024,
  "CD74" => (74 * 60 * 75 * 2048),
  "CD80" => ((79 * 60 * 75) + (57 * 75) + 74) * 2048,
  "DVD-RAM" => 2600000000,
  "DVD"   => 4700000000
}

SIZEMAP.each_key do |media|
  SIZEMAP[media] = (SIZEMAP[media] * SAFE_SPACE).round
end

# Default value
$dists = "unstable".split(',')
$cats  = "main,contrib,non-free".split(',')
$size_limit = ["CD74"]
$src_size_limit = nil
$limit = 0
$popcon = nil
$arches = "i386".split(',')
$dirmap = []
$dirprefix = "Debian"
$dirsrcprefix = "Debian-Src"
$source = true
$merge = false
$ignore_large_packages=false
$include_pkgs = []

# make directory if it doesn't exist.
def install (dir)
  system("/usr/bin/install -d #{dir}")
end

def get_size(size_hash, sizenum)
  size=size_hash[sizenum]
  if size.kind_of?(Integer)
    if size == 0
      return get_size(size_hash, (sizenum - 1))
    end
    return size
  elsif size == nil
    return get_size( size_hash, (sizenum - 1) )
  else
    if SIZEMAP.include?(size)
      return SIZEMAP[size]
    else
      warning "Warning: Unknown Media Name: #{size}"
        return 0
    end
  end
end

class Archive

  def initialize (file)
    @file = file
    @info = {}
  end

  def each (&block)
    info = ""
    fin = Zlib::GzipReader.open(@file)
    fin.each do |line|
      if line == "\n"
	yield info
	info = ""
      else
	info << line
      end
    end
    fin.close
  end

  def info_s (pkgs, fout)
    str = ""
    i = 0
    pkginfo = nil
    pkgs.each do |pkg|
      pkginfo = @info[pkg]
      next unless pkginfo
      pkginfo = pkginfo + "\n"
      if block_given?
        if yield(pkg)
	  fout.write pkginfo
          i+=1
        end
      else
	fout.write pkginfo
        i+=1
      end
    end
    i
  end

  def parse (&block)
    each do |src|
      pkg = yield src
      @info[pkg] = src
    end
  end
  protected :parse

end

class ArchiveDB

  def initialize
    @registered = {}
    @sizedb = {}
  end

  def pkg_size (pkg)
    if @sizedb[pkg] != nil
      return @sizedb[pkg]
    else
      return 0
    end      
  end

  def pkg_size_all (pkgs)
    size = 0
    pkgs.each do |pkg|
      size += pkg_size(pkg)
    end
    size
  end
  
  attr :registered
  attr :sizedb

end

class Packages < Archive

  PKGDB = ArchiveDB.new

  def initialize(packages_gz)
    super(packages_gz)
    @sizedb = {}

    parse { |src|
      pkg = nil
      filename = nil
      src.each_line do |line|
        case line
        when /Package: (\S+)/
          pkg = $1
	  
        when /Filename: (.*)$/
          filename = $1
	  
        when /^Size: (\d+)$/
          @sizedb[pkg] = $1.to_i
          if ! PKGDB.registered.has_key?(filename)
            PKGDB.sizedb[pkg] = 0 if PKGDB.sizedb[pkg] == nil
            PKGDB.sizedb[pkg] += $1.to_i
            PKGDB.registered[filename] = 1
          end
        end
      end
      pkg
    }

  end

  def packages_file_of (pkgs, fout)
    info_s(pkgs, fout)
  end

end

class Sources < Archive

  module SourceFinder
    def sources_of (pkgs)
      hash = {}
      pkgs.each do |pkg|
        src = @bindb[pkg]
        if src then
          hash[src] = 1
        else
          if block_given?
            yield pkg
          end
        end
      end
      hash.keys
    end
  end

  class SrcDB < ArchiveDB

    include SourceFinder

    def initialize
      super
      @bindb = {}
      @warningdb = {}
    end

    def src_size (pkg); pkg_size(pkg); end
    def sources_of(pkg)
      super(pkg) { |pkg|
        if !@warningdb.include?(pkg)
          warning "Warning: Source of #{pkg} not found"
	  @warningdb[pkg] = true
	end
      }
    end

    def src_size_from_bin (bin)
      pkg = sources_of([pkg])[0]
      src_size(pkg)
    end

    def src_size_all (pkgs, write_src)
      size = 0
      i = 0
      pkgs.each do |pkg|
         if ! write_src.include?(pkg)
           size += src_size(pkg)
         end
	i += 1
      end
      size
    end

    def src_size_all_from_bin (bins, write_src)
      src_size_all(sources_of(bins), write_src)
    end

    attr :bindb

  end

  SRCDB = SrcDB.new
  attr :SRCDB

  include SourceFinder

  def initialize (sources_gz)
    super(sources_gz)
    @bindb = {}
    @sizedb = {}
    parse { |src|
      pkg = nil
      dir = nil
      src.each_line do |line|
        case line
        when /Package: (.*)/
          pkg = $1

        when /Binary: (.*)/
          binary = $1.split(', ')
          binary.each do |bi|
            @bindb[bi] = pkg
            SRCDB.bindb[bi] = pkg
          end

	when /Directory: (.*)/
	  dir = $1

        when / \S+ (\d+) (.*)/
          @sizedb[pkg] = 0 if @sizedb[pkg] == nil
          @sizedb[pkg] += $1.to_i

          if ! SRCDB.registered.has_key?(dir + "/" + $2)
            SRCDB.sizedb[pkg] = 0 if SRCDB.sizedb[pkg] == nil 
            SRCDB.sizedb[pkg] += $1.to_i
	    SRCDB.registered[dir + "/" + $2] = 1
          end
          
        end
      end      
      pkg
    }

  end

  def sources_file_of (pkgs, fout, ignore_src = [])
    info_s(pkgs, fout) { |pkg| ! ignore_src.include?(pkg) }
  end

end

class SizeSmallError < RuntimeError; end

class SourcePartition

  def initialize (size_limit, parts_limit)
    @size_limit = size_limit
    @parts_limit = parts_limit
    @nolimit = true if parts_limit < 0
    @parts = []
    @parts << []
    @written = {}
    @size = 0

    @cur_size_limit = get_size(@size_limit, 0)

  end

  def add (pkg)
    return true if @written.include?(pkg)
    srcsize = Sources::SRCDB.src_size(pkg)
    raise SizeSmallError, "Size '#{@cur_size_limit}' is too small to locate source '#{pkg}' in source partition #{parts.size-1}: #{srcsize}" if srcsize > @cur_size_limit
    if @size + srcsize < @cur_size_limit
      @parts.last << pkg
      @size += srcsize
      @written[pkg] = 1
      return true
    else
      if @nolimit || @parts.size < @parts_limit
	last = []
	last << pkg
	@size = srcsize
	@parts << last
        @cur_size_limit = get_size(@size_limit, @parts.size - 1)
	@written[pkg] = 1
	return true
      else
	return false
      end
    end
  end

  attr_accessor :parts_limit
  attr :parts

end

# package separator class
class SizeSeparator

  def initialize (size_limit, src_size_limit, limit = 0)
    @size_limit = size_limit
    @limit = limit
    @source_partition = SourcePartition.new(src_size_limit, limit - 1)
  end

  def separate (pkgs)
    size = pkgs.size 
    done = 0
    sep_pkgs = []
    sep_src = []
    sep_src << []
    write_src = {}
    i = 0
    while done < size
      old_done = done
      old_write_src = write_src.clone if $source == true
      limit = get_size(@size_limit, i)
      begin
        done = calc_pkgs(pkgs, done, write_src, limit)
        sep_pkgs << pkgs.slice(old_done..done)
      rescue SizeSmallError
        raise $! unless $ignore_large_packages
        warning "Warning: Ignoring package '#{pkgs[done]}': " + $!.to_s
        done += 1
        next
      end
      done += 1

      print_info(i, sep_pkgs.last, old_write_src)

      i += 1
      if @limit != 0
	@source_partition.parts_limit -= 1 unless (!$source) || $merge
	j = 0
	j = @source_partition.parts.size unless (!$source) || $merge
	if i + j >= @limit
	  break
	end
      end
    end
    print_source_info(i) unless (!$source) || $merge
    sep_pkgs
  end

  def print_info (partnum, pkg, write_src)
    psize = Packages::PKGDB.pkg_size_all(pkg)
    ssize =  Sources::SRCDB.src_size_all_from_bin(pkg, write_src) if $merge
    print "#{$dirprefix}#{partnum}: #{pkg.size} packages. Size: #{psize}"
    print " + #{ssize} = #{psize + ssize}" if $merge
    print " [ #{pkg[0]}"
    print ", ..." if pkg.size > 1
    print " ]\n"
  end

  def print_source_info (partnum)
    @source_partition.parts.each do |part|
      srcsize = Sources::SRCDB.src_size_all(part, [])
      print "#{$dirsrcprefix}#{partnum}: #{part.size} sources. Size: #{srcsize}"
      print " [ #{part[0]}"
      print ", ..." if part.size > 1
      print " ]\n"
      partnum += 1
    end
  end

  def calc_pkgs (pkgs, left , write_src, limit)
    right = pkgs.size
    start = left
    size = 0
    srcsize = 0
    src = nil
    while left < right

      pkgsize = Packages::PKGDB.pkg_size(pkgs[left])
      if (pkgsize + size) > limit
        raise SizeSmallError, "Size '#{limit}' is too small to " +
          "locate package '#{pkgs[start]}' in partition: size '#{pkgsize}'" if start == left
	break
      end

      if $source == true
	src = Sources::SRCDB.sources_of([pkgs[left]]).first
	if src != nil
	  if $merge 
	    if ! write_src.include?(src) 
	      srcsize = Sources::SRCDB.src_size(src)
	    else
	      srcsize = 0
	    end
	  else
	    begin
	      if @source_partition.add(src) == false
		break
	      end
	    rescue SizeSmallError
	      raise $! if start == left
	      break
	    end
	  end
	else
	  srcsize = 0
	end
        if (pkgsize + srcsize + size) > limit
          raise SizeSmallError, "Size '#{limit}' is too small to " +
            "locate package/source '#{pkgs[start]}' in partition: " +
            "size '#{pkgsize}'/'#{srcsize}'" if start == left
	  break
        end
	write_src[src] = 1
      end

      size += (pkgsize + srcsize)
      left += 1

    end

    return left - 1

  end
  private :calc_pkgs

  attr :source_partition

end

def usage
  $stderr.print "Usage: ", File.basename($0),
    " [--dist=foo[,bar,..] ...] [--section=foo[,bar,..] ...]\n",
    "                  [--help] [--include-from=foo] [--arch=foo] [--limit=num]\n",
    "                  [--dirmap=foo[,bar,..] ...] [--nosource]\n",
    "                  [--ignore-large-packages] [--merge-source]\n",
    "                  [--size=num1[,num2..] ...] [--srcsize=num[,num..] ...]\n",
    "                  [--include=foo[,bar..] ...] <source> <dest>",
    "\n"
end

def error (msg)
  $stderr.puts msg
  exit 1
end

def error_arg (msg)
  $stderr.puts msg
  usage
  exit 1
end

def warning (msg)
  $stderr.puts msg
end

## program start from here

trap("INT") { puts "Interrupted"; exit(0) }

opt_parser = GetoptLong.new
opt_parser.set_options(['--help', '-h', GetoptLong::NO_ARGUMENT],
                       ['--dist', '-d', GetoptLong::REQUIRED_ARGUMENT],
                       ['--section', '-s', GetoptLong::REQUIRED_ARGUMENT],
                       ['--size', '-S', GetoptLong::REQUIRED_ARGUMENT],
                       ['--srcsize', '-R', GetoptLong::REQUIRED_ARGUMENT],
                       ['--include', '-i', GetoptLong::REQUIRED_ARGUMENT],
                       ['--include-from', GetoptLong::REQUIRED_ARGUMENT],
                       ['--arch', '-a', GetoptLong::REQUIRED_ARGUMENT],
                       ['--dirmap', '-D', GetoptLong::REQUIRED_ARGUMENT],
		       ['--dirprefix', GetoptLong::REQUIRED_ARGUMENT],
		       ['--dirsrcprefix', GetoptLong::REQUIRED_ARGUMENT],
                       ['--limit', '-l', GetoptLong::REQUIRED_ARGUMENT],
                       ['--nosource', GetoptLong::NO_ARGUMENT],
                       ['--merge-source', '-m', GetoptLong::NO_ARGUMENT],
                       ['--ignore-large-packages', '-I', GetoptLong::NO_ARGUMENT]);

begin
  opt_parser.each_option do |optname, optargs|
    case optname
    when '--help'
      usage
      exit 0

    when '--dist'
      $dists = optargs.split(',')

    when '--section'
      $cats = optargs.split(',')

    when '--size'
      $size_limit = optargs.split(',')

    when '--srcsize'
      $src_size_limit = optargs.split(',')

    when '--include-from'
      $popcon = optargs

    when '--arch'
      $arches = optargs.split(',')

    when '--dirmap'
      $dirmap = optargs.split(',')

    when '--dirprefix'
      $dirprefix=optargs.to_s

    when '--dirsrcprefix'
      $dirsrcprefix=optargs.to_s

    when '--limit'
      $limit = optargs.to_i

    when '--nosource'
      $source = false

    when '--merge-source'
      $merge = true

    when '--ignore-large-packages'
      $ignore_large_packages = true

    when '--include'
      $include_pkgs.concat(optargs.split(','))

    end
  end
rescue GetoptLong::AmbigousOption, GetoptLong::NeedlessArgument,
       GetoptLong::MissingArgument, GetoptLong::InvalidOption
  usage
  exit 1
end

$dirsrcprefix = $dirprefix if $merge
$src_size_limit = $size_limit unless $src_size_limit

def check_size_option (size_limit)
  size_limit.each_index do |num|
    if /\A\d+\z/ =~ size_limit[num].to_s
      size_limit[num] = size_limit[num].to_i
    elsif ! SIZEMAP.include?(size_limit[num])
      error("Unknown media type #{size_limit[num]}")
    end
  end
end

check_size_option($size_limit)
check_size_option($src_size_limit)

if ARGV.size != 2
  error_arg("two arguments <source> and <dest> required")
end

if $merge && ! $source
  error_arg("--merge and --nosource is given")
end

if ! $merge && $limit == 1
  error_arg("limit must be larger than 1 in no merge-mode")
end

base = ARGV.shift
dest_dir = ARGV.shift

$packages = {}
$arches.each do |arch|
  $dists.each do |dist|
    $cats.each do |cat|
      file = "dists/#{dist}/#{cat}/binary-#{arch}/Packages.gz"
      print "Reading #{file}... "
      $stdout.flush
      begin
        $packages[dist + "/" + cat + "/" + arch] =
          Packages.new("#{base}/#{file}")
      rescue
        puts "failed"
        error($!.to_s)
      end
      puts "done"
    end
  end
end

if $source == true
  $sources = {}
  $dists.each do |dist|
    $cats.each do |cat|
      file = "dists/#{dist}/#{cat}/source/Sources.gz"
      print "Reading #{file}... "
      $stdout.flush
      begin
        $sources[dist + "/" + cat] = Sources.new("#{base}/#{file}")
      rescue
        puts "failed"
        error($!.to_s)
      end
      puts "done"
    end
  end
end

pkgs = []

$include_pkgs.each do |pkg|
  if Packages::PKGDB.sizedb.include?(pkg)
    pkgs << pkg
  else
    warning("Warning: No such package: #{pkg}")
  end
end

if $popcon then
  open($popcon) { |file|
    file.each_line do |line|
      line.chomp!
      pkgs << line if Packages::PKGDB.sizedb.include?(line)
    end
  }
end

if pkgs.empty?
  pkgs = Packages::PKGDB.sizedb.keys
end

size_separator = SizeSeparator.new($size_limit, $src_size_limit, $limit)

begin
  sep_pkgs =  size_separator.separate(pkgs)
rescue SizeSmallError
  error("Error!: " + $!.to_s)
end

def write_packages_gz (name, dist, cat, arch, sep_pkg, dest_dir, dir)
  file = dir + "binary-#{arch}/Packages.gz"
  install(dest_dir + "/" + dir + "binary-#{arch}")
  Zlib::GzipWriter.open(dest_dir + "/" + file) { |gz|
    print "Writing Packages.gz of #{name} for (#{dist},#{cat},#{arch})... "
    $stdout.flush
    i = $packages[dist + "/" + cat + "/" + arch].packages_file_of(sep_pkg, gz)
    print "#{i}.\n"
  }
end

def write_sources_gz (name, dist, cat, sep_pkg, dest_dir, dir, write_src)
  write_src[dist + "/" + cat] = 
    [] if write_src[dist + "/" + cat] == nil
  file = dir + "source/Sources.gz"
  install(dest_dir + "/" + dir + "source")
  Zlib::GzipWriter.open(dest_dir + "/" + file) { |gz|
    print "Writing Sources.gz of #{name} for (#{dist},#{cat})... "
    $stdout.flush
    i = $sources[dist + "/" + cat].sources_file_of(sep_pkg, gz, write_src[dist + "/" + cat])
    sep_pkg.each do |src|
      write_src[dist + "/" + cat] << src
    end
    print "#{i}.\n"
  }
end

def topdir(i)
  dir = $dirmap[i]
  dir = i.to_s unless dir
  dir
end

write_src = {}
$dists.each do |dist|
  $cats.each do |cat|
    i = 0
    distsdir = "dists/" + dist + "/" + cat + "/"
    sep_pkgs.each do |sep_pkg|
      dir = topdir(i) + "/" + distsdir
      $arches.each do |arch|
	write_packages_gz($dirprefix + topdir(i), dist, cat, arch,
			  sep_pkg, dest_dir, $dirprefix + dir)
      end
      write_sources_gz($dirprefix + topdir(i), dist, cat,
			$sources[dist + "/" + cat].sources_of(sep_pkg),
			dest_dir, $dirprefix + dir, write_src) if $merge
      i += 1
    end

    if $source == true && $merge == false
      i = 0 if $dirprefix != $dirsrcprefix
      size_separator.source_partition.parts.each do |sep_pkg|
	write_sources_gz($dirsrcprefix + topdir(i), dist, cat, sep_pkg, dest_dir,
			 $dirsrcprefix + topdir(i) + "/" + distsdir, write_src)
	i += 1
      end
    end

  end
end
