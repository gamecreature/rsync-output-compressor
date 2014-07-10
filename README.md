# rsync-output-compressor

A little script to compress the output of rsync -v into a more useable and customizable summary.


```
receiving incremental file list
/home/emma/public_html/important_file.txt
/home/emma/public_html/important_file1.txt
deleting /home/emma/public_html/old-file.txt
/home/emma/public_html/important_file2.txt
/home/emma/public_html/important_file3.txt
...
/home/sarah/public_html/index.html
/home/sarah/public_html/images/
...
/home/david/private/special_file.txt
/home/david/public_html/downloads/new_download.zip
/home/david/public_html/index.html
```

Can be turned into this:

```
receiving incremental file list
    123    -5 /home/emma/public_html/
     40       /home/sarah/public_html/
      1       /home/david/private/special_file.txt
      2       /home/david/public_html/
```


## Background

The reason I've written this, is because I like the rsync -v option which enables me to see what has been changed.
This is very usefull when making backups with rsync. 
Problem is it shows me EVERYTHING that has changed and usually I don't care about that.

By piping the output of your rsync command to this script the output is filtered by your specification.


## Usage

This script requires a rules file, which describes what needs to be filtered. The rules file is a required
arguments.

The first example shows above could have ben run like this:

```
rsync -avz --delete user@example.com:/data /backups/remote_data | rsync-output-compressor.rb --rules compress-rules.txt
```

The rules file in this example is 'compress-rules.txt'. See the text  below for example rule files



## Example rule files and their output


#### Simple example

The basic rule is that Every path that starts with the given prefix is grouped together.

```
# Starting a line with a '#' is interpreted as a comment
# empty lines are ignored!

/home/emma
/home/sarah
```

```
receiving incremental file list
    123    -5 /home/emma/
     40       /home/sarah/
      1       /home/david/private/special_file.txt
      1       /home/david/public_html/downloads/new_download.zip
      1       /home/david/public_html/index.html
```



#### A normal wildcard *

A wildcard can be used to match a part of the the given path.
This only matches full path-elements! (so you cannot perform a partial name-matches only items between the path-seperators )

```
/home/*/public_html/
```

```
receiving incremental file list
    123    -5 /home/emma/public_html/
     40       /home/sarah/public_html/
      1       /home/david/private/special_file.txt
      2       /home/david/public_html/
```


#### The *! wildcard

By appending a ! after the wildecard symbol, you can make the given wildcard important
and the star isn't replaced by every match.

```
/home/*!/public_html/
```

Normal output. 

```
receiving incremental file list
   163    -5 /home/*/public_html/ 
     1       /home/david/private/special_file.txt
     2       /home/*/public_html/
```


Output with the grouping (-g) option:

```
receiving incremental file list1
   165   -5 /home/*/public_html/ 
     1      /home/david/private/special_file.txt
```

Because the script standard uses a streaming mode when grouping the matches together
a non-matching filename wil flush the current buffer. (This for reducing memory usage and regular flushing).
You can change this behaviour with the grouping option, which matches all lines in memory before flushing them.
Notice though, this will consume more memory.


## Command Line Help

```
Usage: rsync -v ... | rsync-output-compressor --rules=rules.txt [options]

Specific options:
    -f, --full FILENAME              A file that is going to contain the full output
    -r, --rules FILENAME             The rules file (required)
    -g, --group                      Group the results together
    -s, --sort                       Sort the results (enables group mode!)
    -h, --help                       You've already found it!!
```


## Ideas/Wishes

 * A non-implement feature is the use of a no-output operator.  Start the rule line with a '!' should completely swallow the matches.
 * Partial file matches



## Contributing

Please fork and make a pull request.

Or just contact me: rick@blommersit.nl

