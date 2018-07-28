# IO::ChanneledPipe

A IO pipe which uses channel

## Installation

```yaml
  dependencies:
    channeled_pipe:
      github: anykeyh/channeled_pipe
```

Then where useful

```crystal
  require "channeled_pipe"
```

## Channeled Pipe

This works like IO pipe except it will stop writing if allocated buffer
is already full and not yet read.

This is useful to ensure a low consumption of memory while dealing
with larger files.

It's also a useful tool to deal with API which doesn't offer low-level access
to the IO, but reference one IO as argument.

## Usage example:

Imaging you have a pipeline of transformation from file a to file b:
- `transform_1(i, o)`
- `transform_2(i, o)`
- `transform_3(i, o)`

If you want to `in -> t1 -> t2 -> t3 -> o`, you need to use pipes, and stdlib
  offers `IO.pipe`. `IO.pipe` has however few drawbacks:
1/ It lacks any tools to deal with EOF. Your pipe is open and your transforms
   has no clue about when the stream will end unless programmed correctly
2/ You may want to apply your transformations in fiber for improvement in
   performance (it's true for slow IO like sockets). However you face a chance
   to overload your memory if dealing with big IO.
   In case your read a file and write to socket, your pipe will bloat as
   reader is way faster than writter.
3/ It uses unix file descriptors. I don't see how it will be usable in a future
   Windows release of crystal

Channeled Pipe offer to deal with the points above at very low price (see below).

## Real world usages:

- Uploading of large file using multipart/format-data format, without dealing
 with low level HTTP::Client API
- Cluster of applications, with get and transform large datasets, and communicate
  their data through sockets.

## Basic example
```crystal
r, w = ChanneledPipe.new # Create a pipe

spawn do
 4.times do |x|
   w.write(x)
   puts "-> #{x}"
   w.flush # Flushing is done in this example to prevent buffering
 end

 w.close # <- won't close before the pipe content has been consumed.
end

while (!r.closed?)
 puts "<- #{r.gets}"
end
```
Output:

```
-> 1
<- 1
-> 2
<- 2
-> 3
<- 3
-> 4
<- 4
```

Above, the output is sync and the pipe write operation are stopped until the
read operations are done.

## Real life example

Uploading a file:
- We want to use fiber to increase performance dealing with socket and file IO.
- We don't have access to the underlying Socket IO object; the API offers however
  to pass an input IO for the body of our request.
- We want to prevent loading all the content of the uploaded file in memory

```crystal
r, w = IO::ChanneledPipe.new

spawn do
 w.write("--foo\n".to_slice)
 w.write("Content-Type: application/binary\n\n".to_slice)
 IO.copy(f, w)
 w.write("--foo--")
 w.close
end

HTTP::Client.post(url: "https://example.com/file/upload", headers: {
  "Content-Type" => "multipart/form-data",
  "Content-Length" => compute_content_length
}, body: r)
```

## Pros

- Managed memory consumption (default: around 8Kb per pipe)
- Compared to pipe, no file descriptors / no system call (using Channel instead)

## Cons

- Memory copy on write: Chunk of datastream are copied temporarly
 in memory while transfer. Can be performance costly in some case
- Do not work with forking, in contrast with basic `IO.pipe`.

## Advanced usage & notes

- `IO::ChanneledPipe` uses `IO::Buffered`, so `ChanneledPipe` wait until the internal buffer is full
  before sending through the pipe the data.
  This can be prevented by using `flush`.
  `write` will queued until the pipe is emptied first by `read`.
  It's possible to increase the number of chunks before queuing by using parameter at
  construction:

  ```crystal
    r,w = IO::ChanneledPipe.new 32 #32 chunks of 8kb before queuing the write operation
  ```

- `close` won't close straight the pipe but will let the reader to consume the
  chunks of data in the stream before closing the pipe.
  Therefore, `close` is only allowed on `write` side of the pipe.
  Method can then react by `EOF` exception on the read call (e.g. with read_lines)

- A method `closing?` is set to true if `close` has been called but there's still
  data in the pipe. Write will then be prevented, while read is still possible.

- Finally, you can force closing ASAP using `close_channel` method. This will
  throw exception on current writer/reader of the pipe, and further write/read will
  be prevented