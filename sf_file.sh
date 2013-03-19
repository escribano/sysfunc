#
# Copyright 2010 - Francois Laupretre <francois@tekwire.net>
#
#=============================================================================
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License (LGPL) as
# published by the Free Software Foundation, either version 3 of the License,
# or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#=============================================================================

#=============================================================================
# Section: File/dir management
#=============================================================================

##----------------------------------------------------------------------------
# Recursively deletes a file or a directory
#
# Returns without error if arg is a non-existent path
#
# Args:
#	$1 : Path to delete
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_delete()
{
typeset i

for i
	do
	if ls -d "$i" >/dev/null 2>&1 ; then
		sf_msg1 "Deleting $i"
		[ -z "$sf_noexec" ] && \rm -rf $i
	fi
done
}

##----------------------------------------------------------------------------
# Find an executable file
#
# Args:
#	$1 : Executable name
#	$2 : Optional. List of directories to search. If not search, use PATH
# Returns: Always 0
# Displays: Absolute path if found, nothing if not found
#-----------------------------------------------------------------------------

sf_find_executable()
{
typeset file dirs dir f

file="$1"
shift
dirs="$*"
[ -z "$dirs" ] && dirs="$PATH"
dirs="`echo $dirs | sed 's/:/ /g'`"

for dir in $dirs
	do
	f="$dir/$file"
	if [ -f "$f" -a -x "$f" ] ; then
		echo "$f"
		break
	fi
done
}

##----------------------------------------------------------------------------
# Creates a directory
#
# If the given path argument corresponds to an already existing
# file (any type except directory or symbolic link to a directory), the
# program aborts with a fatal error. If you want to aAlways 0
# this (if you want to create the directory, even if somathing else is
# already existing in this path), call sf_delete first.
# If the path given as arg contains a symbolic link pointing to an existing
# directory, it is left as-is.
#
# Args:
#	$1 : Path
#	$2 : Optional. Directory owner[:group]. Default: root
#	$3 : Optional. Directory mode in a format accepted by chmod. Default: 755
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_create_dir()
{

typeset path owner mode

path=$1
owner=$2
mode=$3

[ -z "$owner" ] && owner=root
[ -z "$mode" ] && mode=755

if [ ! -d "$path" ] ; then
	sf_msg1 "Creating directory: $path"
	if [ -z "$sf_noexec" ] ; then
		mkdir -p "$path"
		[ -d "$path" ] || sf_fatal "$path: Cannot create directory"
		sf_chown $owner $path
		sf_chmod $mode "$path"
	fi
fi
}

##----------------------------------------------------------------------------
# Saves a file
#
# No action if the 'sf_nosave' environment variable is set to a non-empty string.
#
# If the input arg is the path of an existing regular file, the file is copied
# to '$path.orig'
# TODO: improve save features (multiple numbered saved versions,...)
# Args:
#	$1 : Path
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_save()
{
[ "X$sf_nosave" = X ] || return
if [ -f "$1" -a ! -f "$1.orig" ] ; then
	sf_msg1 "Saving $1 to $1.orig"
	[ -z "$sf_noexec" ] && cp -p "$1" "$1.orig"
fi
}

##----------------------------------------------------------------------------
# Renames a file to '<dir>/old.<filename>
# 
# Args:
#	$1 : Path
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_rename_to_old()
{
typeset dir base of f

f="$1"
[ -f "$f" ] || return
dir="`dirname $f`"
base="`basename $f`"
of="$dir/old.$base"
sf_msg1 "Renaming $f to old.$base"
if [ -z "$sf_noexec" ] ; then
	sf_delete $of
	mv $f $of
fi
}

##----------------------------------------------------------------------------
# Copy a file or the content of function's standard input to a target file
#
# The copy takes place only if the source and target files are different.
# If the target file is already existing, it is saved before being overwritten.
# If the target path directory does not exist, it is created.
#
# Args:
#	$1: Source path. Special value: '-' means that data to copy is read from
#		stdin, allowing to produce dynamic content without a temp file.
#	$2: Target path
#	$3: Optional. File creation mode. Default=644
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_check_copy()
{
typeset mode source target

istmp=''
source="$1"

#-- Special case: source='-' => read data from stdin and create temp file

if [ "X$source" = 'X-' ] ; then
	source=$sf_tmpfile._check_copy
	dd of=$source 2>/dev/null
fi

target="$2"

mode="$3"
[ -z "$mode" ] && mode=644

[ -f "$source" ] || return

if [ -f "$target" ] ; then
	diff "$source" "$target" >/dev/null 2>&1 && return
	sf_save $target
fi

sf_msg1 "Updating file $target"

if [ -z "$sf_noexec" ] ; then
	\rm -rf "$target"
	sf_create_dir `dirname $target`
	cp "$source" "$target"
	sf_chmod $mode "$target"
fi
}

##----------------------------------------------------------------------------
# Replaces or prepends/appends a data block in a file
#
# The block is composed of entire lines and is surrounded by special comment
# lines when inserted in the target file. These comment lines identify the
# data block and allow the function to be called several times on the same
# target file with different data blocks. The block identifier is the
# base name of the source path.
#- If the given block is not present in the target file, it is appended or
# prepended, depending on the flag argument. If the block is already
# present in the file (was inserted by a previous run of this function),
# its content is compared with the new data, and replaced if different.
# In this case, it is replaced at the exact place where the previous block
# lied.
#- If the target file exists, it is saved before being overwritten.
#- If the target path directory does not exist, it is created.
#
# Args:
#	$1: If this arg starts with the '-' char, the data is to be read from
#		stdin and the string after the '-' is the block identifier.
#-		If it does not start with '-', it is the path to the source file
#		(containing the data to insert).
#	$2: Target path
#	$3: Optional. Target file mode.
#-		Default=644
#	$4: Optional. Flag. Set to 'prepend' to add data at the beginning of
#		the file.
#-		Default mode: Append.
#-		Used only if data block is not already present in the file.
#-		Can be set to '' (empty string) to mean 'default mode'.
#	$5: Optional. Comment character.
#-		This argument, if set, must contain only one character.
#		This character will be used as first char when building
#		the 'identifier' lines surrounding the data block.
#-		Default: '#'.
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_check_block()
{
typeset mode source target flag comment nstart nend fname tmpdir

source="$1"
target="$2"
mode="$3"
[ -z "$mode" ] && mode=644
flag="$4"
comment="$5"
[ -z "$comment" ] && comment='#'

# Special case: data read from stdin. Create file in temp dir (id taken from
# the base name)

echo "X$source" | grep '^X-' >/dev/null 2>&1
if [ $? = 0 ] ; then
	fname="`echo "X$source" | sed 's/^..//'`"
	fname=`basename $fname`
	tmpdir=$sf_tmpfile._dir.check_block
	\rm -rf $tmpdir
	mkdir -p $tmpdir
	source=$tmpdir/$fname
	dd of=$source 2>/dev/null
else
	fname=`basename $source`
fi

[ -f "$source" ] || return

#-- Extrait bloc

if [ -f "$target" ] ; then
	nstart=`grep -n "^.#sysfunc_start/$fname##" "$target" | sed 's!:.*$!!'`
	if [ -n "$nstart" ] ; then
		( [ $nstart != 1 ] && head -`expr $nstart - 1` "$target" ) >$sf_tmpfile._start
		tail -n +`expr $nstart + 1` <"$target" >$sf_tmpfile._2
		nend=`grep -n "^.#sysfunc_end/$fname##" "$sf_tmpfile._2" | sed 's!:.*$!!'`
		if [ -z "$nend" ] ; then # Corrupt block
			sf_fatal "check_block($1): Corrupt block detected - aborting"
			return
		fi
		( [ $nend != 1 ] && head -`expr $nend - 1` $sf_tmpfile._2 ) >$sf_tmpfile._block
		tail -n +`expr $nend + 1` <$sf_tmpfile._2 >$sf_tmpfile._end
		diff "$source" $sf_tmpfile._block >/dev/null 2>&1 && return # Same block, no action
		action='Replacing'
	else
		if [ "$flag" = "prepend" ] ; then
			>$sf_tmpfile._start
			cp $target $sf_tmpfile._end
			action='Prepending'
		else
			cp $target $sf_tmpfile._start
			>$sf_tmpfile._end
			action='Appending'
		fi
	fi
	sf_save $target
else
	action='Creating from'
	>$sf_tmpfile._start
	>$sf_tmpfile._end
fi

sf_msg1 "$target: $action data block"

if [ -z "$sf_noexec" ] ; then
	\rm -f "$target"
	sf_create_dir `dirname $target`
	(
	cat $sf_tmpfile._start
	echo "$comment#sysfunc_start/$fname##------ Don't remove this line"
	cat $source
	echo "$comment#sysfunc_end/$fname##-------- Don't remove this line"
	cat $sf_tmpfile._end
	) >$target
	sf_chmod $mode "$target"
fi
}

##----------------------------------------------------------------------------
# Checks if a file contains a block inserted by sf_check_block
#
#
# Args:
#       $1: The block identifier or source path
#       $2: File path
# Returns: 0 if the block is in the file, !=0 if not.
# Displays: Nothing
#-----------------------------------------------------------------------------

sf_contains_block()
{
typeset id target

id="`basename $1`"
target="$2"

grep "^.#sysfunc_start/$id##" "$target" >/dev/null 2>&1
}

##----------------------------------------------------------------------------
# Change the owner of a set of files/dirs
#
# Args:
#       $1: owner[:group]
#       $2+: List of paths
# Returns: chown status code
# Displays: Nothing
#-----------------------------------------------------------------------------

sf_chown()
{
typeset status owner

status=0
owner=$1
shift
if [ -z "$sf_noexec" ] ; then
	chown "$owner" $*
	status=$?
fi
return $status
}

##----------------------------------------------------------------------------
# Change the mode of a set of files/dirs
#
# Args:
#       $1: mode as accepted by chmod
#       $2+: List of paths
# Returns: chmod status code
# Displays: Nothing
#-----------------------------------------------------------------------------

sf_chmod()
{
typeset status mode

status=0
mode=$1
shift
if [ -z "$sf_noexec" ] ; then
	chmod "$mode" $*
	status=$?
fi
return $status
}

##----------------------------------------------------------------------------
# Creates or modifies a symbolic link
#
# The target is saved before being modified.
# Note: Don't use 'test -h' (not portable)
# If the target path directory does not exist, it is created.
#
# Args:
#	$1: Link target
#	$2: Link path
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_check_link()
{
typeset link_target

\ls -ld "$2" >/dev/null 2>&1
if [ $? = 0 ] ; then
	\ls -ld "$2" | grep -- '->' >/dev/null 2>&1
	if [ $? = 0 ] ; then
		link_target=`\ls -ld "$2" | sed 's/^.*->[ 	]*//'`
		[ "$link_target" = "$1" ] && return
	fi
	sf_save "$2"
fi

sf_msg1 "$2: Updating symbolic link"

if [ -z "$sf_noexec" ] ; then
	\rm -rf "$2"
	sf_create_dir `dirname $2`
	ln -s "$1" "$2"
fi
}

##----------------------------------------------------------------------------
# Comment one line in a file
#
# The first line containing the (grep) pattern given in argument will be commented
# out by prefixing it with the comment character.
# If the pattern is not contained in the file, the file is left unchanged.
#
# Args:
#	$1 = File path
#	$2 = Pattern to search (grep regex syntax)
#	$3 = Optional. Comment char (one char string). Default='#'
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_comment_out()
{
typeset com

if [ -z "$3" ] ; then com='#' ; else com="$3"; fi

grep -v "^[ 	]*$com" "$1" | grep "$2" >/dev/null 2>&1
if [ $? = 0 ] ; then
	sf_save "$1"
	sf_msg1 "$1: Commenting out '$2'"
	if [ -z "$sf_noexec" ] ; then
		ed $1 <<-EOF >/dev/null 2>&1
			?^[^$com]*$2?
			s?^?$com?
			w
			q
		EOF
	fi
fi
}

##----------------------------------------------------------------------------
# Uncomment one line in a file
#
# The first commented line containing the (grep) pattern given in argument
# will be uncommented by removing the comment character.
# If the pattern is not contained in the file, the file is left unchanged.
#
# Args:
#	$1 = File path
#	$2 = Pattern to search (grep regex syntax)
#	$3 = Optional. Comment char (one char string). Default='#'
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_uncomment()
{
typeset com

if [ -z "$3" ] ; then com='#' ; else com="$3"; fi

grep "$2" "$1" | grep "^[ 	]*$com" >/dev/null 2>&1
if [ $? = 0 ] ; then
	sf_save "$1"
	sf_msg1 "$1: Uncommenting '$2'"
	if [ -z "$sf_noexec" ] ; then
		ed $1 <<-EOF >/dev/null 2>&1
			?^[ 	]*$com.*$2?
			s?^[ 	]*$com??g
			w
			q
		EOF
	fi
fi
}

##----------------------------------------------------------------------------
# Checks if a given line is contained in a file
#
# Takes a pattern and a string as arguments. The first line matching the
# pattern is compared with the string. If they are different, the string
# argument replaces the line in the file. If they are the same, the file
# is left unchanged.
# If the pattern is not found, the string arg is appended to the file.
# If the file does not exist, it is created.
#
# Args:
#	$1: File path
#	$2: Pattern to search
#	$3: Line string
# Returns: Always 0
# Displays: Info msg
#-----------------------------------------------------------------------------

sf_check_line()
{
typeset file pattern line fline qpattern

file="$1"
pattern="$2"
line="$3"

fline=`grep "$pattern" $file 2>/dev/null | head -1`
[ "$fline" = "$line" ] && return
sf_save $file
if [ -n "$fline" ] ; then
	sf_msg1 "$1: Replacing '$2' line"
	qpattern=`echo "$pattern" | sed 's!/!\\\\/!g'`
	[ -z "$sf_noexec" ] && ed $file <<-EOF >/dev/null 2>&1
		/$qpattern/
		.c
		$line
		.
		w
		q
	EOF
else
	sf_msg1 "$1: Appending '$2' line"
	[ -z "$sf_noexec" ] && echo "$line" >>$file
fi
}

#=============================================================================