class IO::ChanneledPipe < IO
  include IO::Buffered

  @channel : Channel(Bytes?)
  @direction : Symbol
  @buffer : Bytes?

  getter? closing = false

  protected def initialize(@channel, @direction)
  end

  def unbuffered_read(slice : Bytes)
    raise "Read side of the pipe" if @direction == :w

    current_buffer = @buffer

    if current_buffer
      consumed_bytes = {slice.size, current_buffer.size}.min
      slice.copy_from(current_buffer.pointer(0), consumed_bytes)

      if current_buffer.size == consumed_bytes
        @buffer = nil
      else
        @buffer = current_buffer[consumed_bytes,
          current_buffer.size - consumed_bytes]
      end

      return consumed_bytes
    else
      channel_buff = @channel.receive

      if channel_buff
        consumed_bytes = {channel_buff.size, slice.size}.min
        slice.copy_from(channel_buff.pointer(0), consumed_bytes)

        if (channel_buff.size - consumed_bytes) > 0
          @buffer = channel_buff[consumed_bytes,
            channel_buff.size - consumed_bytes]
        end
      else
        @channel.close
        return 0
      end
    end

    return consumed_bytes
  end

  def unbuffered_write(slice : Bytes)
    raise "Write not allowed on read side of the pipe" if @direction == :r
    raise "Unable to write: Pipe is closed/closing" if @closing || @closed
    @channel.send slice.clone
  end

  def closed?
    @channel.closed?
  end

  def close_channel
    @channel.close
  end

  def unbuffered_flush
    # Nothing to do here.
  end

  def unbuffered_rewind
    raise "Rewind is not allowed on pipe"
  end

  def close
    raise "Pipe closing must be done by write side, not read side." unless @direction == :w
  end

  def unbuffered_close
    unless @closing
      @closing = true
      @channel.send nil
    end
  end

  def self.new(mem = IO::Buffered::BUFFER_SIZE)
    mem = IO::Buffered::BUFFER_SIZE if mem <= 0

    capacity = (mem / IO::Buffered::BUFFER_SIZE) +
               ((mem % IO::Buffered::BUFFER_SIZE != 0) ? 1 : 0)

    channel = Channel(Bytes?).new(capacity: mem)

    {
      ChanneledPipe.new(channel, :r),
      ChanneledPipe.new(channel, :w),
    }
  end
end
