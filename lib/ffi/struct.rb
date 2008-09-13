require 'ffi/platform'
module FFI
  class StructLayout
    def initialize(fields, size)
      @fields = fields
      @size = size
    end
    
    def [](name)
      @fields[name]
    end
    def size
      @size
    end
  end
  class StructLayoutBuilder
    LONG_ALIGN = Platform::ARCH =~ /sparc.*/ ? 64 : Platform::LONG_SIZE
    ADDRESS_ALIGN = Platform::ARCH =~ /sparc.*/ ? 64 : Platform::ADDRESS_SIZE
    FLOAT_ALIGN = Platform::ARCH =~ /sparc.*/ ? 64 : Platform::ADDRESS_SIZE
    DOUBLE_ALIGN = Platform::ARCH =~ /sparc.*/ ? 64 : Platform::ADDRESS_SIZE
    class Field
      def initialize(off)
        @off = off
      end
      
      def offset
        @off
      end
      def size
        self.size
      end
      def align
        self.align
      end
      def self.align
        self.size
      end
    end
    class Signed8 < Field
      def self.size; 8; end
      def put(ptr, val)
        ptr.put_int8(@off, val)
      end
      def get(ptr)
        ptr.get_int8(@off)
      end
    end
    class Unsigned8 < Field
      def self.size; 8; end
      def put(ptr, val)
        ptr.put_uint8(@off, val)
      end
      def get(ptr)
        ptr.get_uint8(@off)
      end
    end
    class Signed16 < Field
      def self.size; 16; end
      def put(ptr, val)
        ptr.put_int16(@off, val)
      end
      def get(ptr)
        ptr.get_int16(@off)
      end
    end
    class Unsigned16 < Field
      def self.size; 16; end
      def put(ptr, val)
        ptr.put_uint16(@off, val)
      end
      def get(ptr)
        ptr.get_uint16(@off)
      end
    end
    class Signed32 < Field
      def self.size; 32; end
      def put(ptr, val)
        ptr.put_int32(@off, val)
      end
      def get(ptr)
        ptr.get_int32(@off)
      end
    end
    class Unsigned32 < Field
      def self.size; 32; end
      def put(ptr, val)
        ptr.put_uint32(@off, val)
      end
      def get(ptr)
        ptr.get_uint32(@off)
      end
    end
    class Signed64 < Field
      def self.size; 64; end
      def self.align; LONG_ALIGN; end
      def put(ptr, val)
        ptr.put_int64(@off, val)
      end
      def get(ptr)
        ptr.get_int64(@off)
      end
    end
    class Unsigned64 < Field
      def self.size; 64; end
      def self.align; LONG_ALIGN; end
      def put(ptr, val)
        ptr.put_uint64(@off, val)
      end
      def get(ptr)
        ptr.get_uint64(@off)
      end
    end
    def initialize
      @fields = {}
      @size = 0
    end
    def add_field(name, type, offset=nil)
      field_class = case type
      when :char, NativeType::INT8
        Signed8
      when :uchar, NativeType::UINT8
        Unsigned8      
      when :short, NativeType::INT16
        Signed16
      when :ushort, NativeType::UINT16
        Unsigned16
      when :long, NativeType::LONG
        FFI::Platform::LONG_SIZE == 32 ? Signed32 : Signed64
      when :ulong, NativeType::ULONG
        FFI::Platform::LONG_SIZE == 32 ? Unsigned32 : Unsigned64
      when :int, NativeType::INT32
        Signed32
      when :uint, NativeType::UINT32
        Unsigned32
      when :long_long, NativeType::INT64
        Signed64
      when :ulong_long, NativeType::UINT64
        Unsigned64
      else
        raise ArgumentError, "Unknown type: #{type}"
      end
      
      size = field_class.size / 8
      off = offset ? offset.to_i : align(@size, field_class.align)
      @fields[name] = field_class.new(off)
      @size = off + size
    end
    def build
      StructLayout.new @fields, @size
    end
    def align(offset, bits)
      bytes = bits / 8
      mask = bytes - 1;
      off = offset;
      ((off & mask) != 0) ? (off & ~mask) + bytes : off
    end
  end
  class BaseStruct
    Buffer = FFI::MemoryPointer
    attr_reader :pointer

    def initialize(pointer = nil, *spec)
      @cspec = self.class.layout(*spec)

      if pointer then
        @pointer = pointer
      else
        @pointer = MemoryPointer.new size
      end
    end
    def self.alloc_inout(clear = true)
      self.new(Buffer.alloc_inout(@size, 1, clear))
    end
    def self.alloc_in(clear = true)
      self.new(Buffer.alloc_in(@size, 1, clear))
    end
    def self.alloc_out(clear = true)
      self.new(Buffer.alloc_out(@size, 1, clear))
    end
    def self.size
      @size
    end
    def self.members
      @layout.members
    end
    def size
      self.class.size
    end
    def [](field)
      @cspec[field].get(@pointer)
    end
    def []=(field, val)
      @cspec[field].put(@pointer, val)
    end
    def members
      @cspec.members
    end
    def values
      @cspec.members.map { |m| self[m] }
    end
    def clear
      @pointer.clear
      self
    end
  end
  class Struct < BaseStruct
    def self.jruby_layout(spec)
      raise "Ruby version not supported" if RUBY_VERSION =~ /1.8.*/
      builder = FFI::StructLayoutBuilder.new
      spec[0].each do |name,type|
        builder.add_field(name, FFI.find_type(type))
      end
      builder.build
    end
    def self.rubinius_layout(spec)
      builder = FFI::StructLayoutBuilder.new
      i = 0
      while i < spec.size
        name, type, offset = spec[i, 3]
      
        code = FFI.find_type(type)
        builder.add_field(name, code, offset)
        i += 3
      end
      builder.build
    end
    def self.layout(*spec)

      return @layout if spec.size == 0
      cspec = spec[0].kind_of?(Hash) ? jruby_layout(spec) : rubinius_layout(spec)

      @layout = cspec unless self == FFI::Struct
      @size = cspec.size
      return cspec
    end
    def self.config(base, *fields)
      config = Config::CONFIG
      @size = config["#{base}.sizeof"]
    
      builder = StructLayoutBuilder.new
    
      fields.each do |field|
        offset = config["#{base}.#{field}.offset"]
        size   = config["#{base}.#{field}.size"]
        type   = config["#{base}.#{field}.type"]
        type   = type ? type.to_sym : FFI.size_to_type(size)

        code = FFI.find_type type
        if (code == NativeType::CHAR_ARRAY)
          builder.add_char_array(field.to_s, size, offset)
        else
          builder.add_field(field.to_s, code, offset)
        end
      end
      cspec = builder.build
    
      @layout = cspec
      @size = cspec.size if @size < cspec.size
    
      return cspec
    end
  end
end