#!/usr/bin/ruby
#
# debcopy - Debian Packages/Sources partial copy tool
#
# Usage: debcopy [-l] <source> <dest>
#
#  where <source> is a top directory of a debian archive,
#  and <dest> is a top directory of a new debian partial archive.
#
#  debcopy searches all Packages.gz and Sources.gz under <dest>/dists
#  and copies all files listed in the Packages.gz and Sources.gz
#  files into <dest> from <source>. -l creates symbolic links
#  instead of copying files.
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
require 'getoptlong'
require 'zlib'
require 'fileutils'

$link = false

def usage
  $stderr.puts "Usage: #{__FILE__} [-l] <source> <dest>"
   exit 1
end

def each (file, &block)
  fin = Zlib::GzipReader.open(file)
  fin.each do |line|
    yield line
  end
  fin.close
end

def each_file (file, &block)
  each(file) do |line|
    if /Filename: (.*)/ =~ line
      yield $1
    end
  end
end

def each_sourcefile (file, &block)
  dir = nil
  each(file) do |line|
    case line
    when /^Directory: (.*)$/
      dir = $1
    when /^ \S+ \d+ (\S+)$/
      yield dir + "/" + $1
    end
  end
end

def calc_relpath (source, dest)

  pwd = Dir::pwd

  Dir::chdir source
  source = Dir::pwd
  Dir::chdir pwd
  Dir::chdir dest
  dest = Dir::pwd
  Dir::chdir pwd

  src_ary = source.split("/")
  src_ary.shift
  dest_ary = dest.split("/")
  dest_ary.shift

  return dest if src_ary[0] != dest_ary[0]

  src_ary.clone.each_index do |i|
    break if src_ary[0] != dest_ary[0]
    src_ary.shift
    dest_ary.shift
  end

  src_ary.size.times do |i|
    dest_ary.unshift("..")
  end

  dest_ary.join("/")

end

def do_copy(path)
  if $link
    pwd=calc_relpath(File.dirname($dest_dir + "/" + path), $source_dir)
    File.symlink(pwd + "/" + path, $dest_dir + "/" + path)
  else
    File.copy($source_dir + "/" + path, $dest_dir + "/" + path)
  end
end

def copy(path)

  s=$source_dir + "/" + path
  d=$dest_dir + "/" + path

  if FileTest.exist?(d)
    $stats["ignore"] += 1
    return
  end
  if FileTest.exist?(s)
    FileUtils.mkpath(File.dirname(d))
    do_copy(path)
    $stats["copy"] += 1
  else
    $stats["notfound"] += 1
    $stderr.puts s + " not found."
  end
end

opts = GetoptLong.new(["--symlink", "-l", GetoptLong::NO_ARGUMENT],
		      ["--help", "-h", GetoptLong::NO_ARGUMENT])

opts.each do |opt,arg|
  case opt
  when "--symlink"
    $link = true
  when "--help"
    usage
  end
end

usage if ARGV.size != 2

$source_dir = ARGV.shift
$dest_dir = ARGV.shift

if $link
  $source_dir = Dir::pwd + "/" + $source_dir unless $source_dir =~ /\A\//
  $dest_dir = Dir::pwd + "/" + $dest_dir unless $dest_dir =~ /\A\//
end

$stats = {}
$stats["ignore"] = 0
$stats["copy"] = 0
$stats["notfound"] = 0

open("|find #{$dest_dir}/dists -name Packages.gz") do |o|
  o.each_line do |file|
    file.chomp!
    print "Processing #{file}... "
    $stdout.flush
    each_file(file) do |path|
      copy(path)
    end
    puts "done"
  end
end
open("|find #{$dest_dir}/dists -name Sources.gz") do |o|
  o.each_line do |file|
    file.chomp!
    print "Processing #{file}... "
    $stdout.flush
    each_sourcefile(file.chomp) do |path|
      copy(path)
    end
    puts "done"
  end
end

puts "Number of Copied Files: " + $stats["copy"].to_s
puts "Number of Ignored Files: " + $stats["ignore"].to_s
puts "Number of Non-existence File: " + $stats["notfound"].to_s
