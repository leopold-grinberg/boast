module BOAST

  # Base class for BOAST data types. Inherited class will define a functor.
  class DataType
    include Intrinsics
    include PrivateStateAccessor

    def self.inherited(child)
      child.extend( VarFunctor)
    end

    def vector?
      return @vector_length && ( @vector_length.kind_of?(Variable) || @vector_length > 1 )
    end

    def scalar?
      return !vector?
    end

    def vector_scalar?
      return @vector_length && !@vector_length.kind_of?(Variable) && @vector_length == 1
    end

    def meta_vector?
      return @vector_length && @vector_length.kind_of?(Variable)
    end

  end

  # @!parse module VarFunctors; var_functorize Sizet; end
  class Sizet < DataType

    attr_reader :signed
    attr_reader :size
    attr_reader :vector_length

    def initialize(hash={})
      if hash[:signed] != nil then
        @signed = hash[:signed]
      end
      @size = nil
      @vector_length = nil
    end

    def to_hash
      return { :signed => @signed }
    end

    def copy(options={})
      hash = to_hash
      options.each { |k,v|
        hash[k] = v
      }
      return Sizet::new(hash)
    end

    def decl
      return "integer(kind=#{get_default_int_size})" if lang == FORTRAN
      unless @signed then
        return "size_t" if [C, CL, CUDA, HIP].include?( lang )
      else
        return "ptrdiff_t" if [C, CL, CUDA, HIP].include?( lang )
      end
    end

    def decl_ffi
      return :size_t
    end

    def signed?
      return signed
    end

    def suffix
      s = ""
      return s
    end

  end
 
  # @!parse module VarFunctors; var_functorize Intptr; end
  class Intptrt < DataType

    attr_reader :signed
    attr_reader :size
    attr_reader :vector_length

    def initialize(hash={})
      if hash[:signed] != nil then
        @signed = hash[:signed]
      else
        @signed = get_default_int_signed
      end
      @size = nil
      @vector_length = nil
    end

    def to_hash
      return { :signed => @signed }
    end

    def copy(options={})
      hash = to_hash
      options.each { |k,v|
        hash[k] = v
      }
      return Sizet::new(hash)
    end

    def decl
      return "integer(kind=#{get_default_int_size})" if lang == FORTRAN
      unless @signed then
        return "uintptr_t" if [C, CL, CUDA, HIP].include?( lang )
      else
        return "intptr_t" if [C, CL, CUDA, HIP].include?( lang )
      end
    end

    def decl_ffi
      return :intptr_t
    end

    def signed?
      return signed
    end

    def suffix
      s = ""
      return s
    end

  end

  class Void < DataType

    def initialize(hash={})
    end

    def to_hash
      {}
    end

    def copy(hash={})
      Void::new
    end

    def signed?
      raise "Void cannot be completed!"
    end

    def decl
      raise "Void is unsupported in Fortran!" if lang == FORTRAN
      return "void" if [C, CL, CUDA, HIP].include?( lang )
    end

    def decl_ffi
      raise "Void cannot be completed!"
    end

    def suffix
      ""
    end

  end

  # @!parse module VarFunctors; var_functorize Pointer; end
  class Pointer < DataType
    attr_reader :type
    attr_reader :size
    attr_reader :signed
    attr_reader :vector_length

    def initialize(hash={})
      if hash[:type].nil?
        @type = Void::new
      else
        if hash[:type].kind_of? Class
          @type = hash[:type]::new
        else
          @type = hash[:type]
        end
      end
    end

    def to_hash
      { type: @hash }
    end

    def copy(options={})
      hash = to_hash
      options.each { |k,v|
        hash[k] = v
      }
      Pointer::new(hash)
    end

    def signed?
    end

    def decl
#      return "#{@type.decl}, pointer" if lang == FORTRAN
      raise "Pointers are unsupported in Fortran!" if lang == FORTRAN
      return "#{@type.decl} *" if [C, CL, CUDA, HIP].include?( lang )
    end

    def decl_ffi
      :pointer
    end

    def suffix
      ""
    end

  end

  # @!parse module VarFunctors; var_functorize Real; end
  class Real < DataType

    attr_reader :size
    attr_reader :signed
    attr_reader :vector_length
    attr_reader :total_size
    attr_reader :getters
    attr_reader :setters

    def ==(t)
      vlt = t.vector_length
      vlt = ( vlt ? vlt : 1 )
      vl = vector_length
      vl = ( vl ? vl : 1 )
      return true if t.class == self.class and t.size == size and vlt == vl
      return false
    end

    # Creates a new instance of Real.
    # @param [Hash] hash contains named properties for the type
    # @option hash [Integer] :size size of the Real type in byte. By default {BOAST.get_default_real_size}.
    # @option hash [Integer] :vector_length length of the vector of Real. By default 1.
    def initialize(hash={})
      if hash[:size] then
        @size = hash[:size]
      else
        @size = get_default_real_size
      end
      @vector_length = hash[:vector_length]
      if @vector_length
        @total_size = @size*@vector_length
      else
        @total_size = @size
      end
      @signed = true
    end

    def signed?
      return signed
    end

    def to_hash
      return { :size => @size, :vector_length => @vector_length }
    end

    def copy(options={})
      hash = to_hash
      options.each { |k,v|
        hash[k] = v
      }
      return Real::new(hash)
    end

    def decl
      return "real(kind=#{@size})" if lang == FORTRAN
      if vector? && !meta_vector?
        if [CL, CUDA, HIP].include?( lang ) then
          return "float#{@vector_length}" if @size == 4
          return "double#{@vector_length}" if @size == 8
        elsif lang == C then
          return get_vector_decl(self)
        end
      end
      return "float" if @size == 4
      return "double" if @size == 8
    end

    def decl_ffi
      if lang == FORTRAN && ( @vector_length.kind_of?(Variable) || vector? )
        return :pointer
      end
      t = ""
      t << "float" if @size == 4
      t << "double" if @size == 8
      t << "x#{@vector_length}" if vector?
      return t.to_sym
    end

    def suffix
      s = ""
      if [C, CL, CUDA, HIP].include?( lang ) then
        s << "f" if @size == 4
      elsif lang == FORTRAN then
        s << "_wp" if @size == 8
      end
      return s
    end

  end

  # @!parse module VarFunctors; var_functorize Int; end
  class Int < DataType

    attr_reader :size
    attr_reader :signed
    attr_reader :vector_length
    attr_reader :total_size

    def ==(t)
      vlt = t.vector_length
      vlt = ( vlt ? vlt : 1 )
      vl = vector_length
      vl = ( vl ? vl : 1 )
      return true if t.class == self.class && t.signed == signed && t.size == size && vlt == vl
      return false
    end

    # Creates a new instance of Int.
    # @param [Hash] hash contains named properties for the type
    # @option hash [Integer] :size size of the Int type in byte. By default {BOAST.get_default_int_size}.
    # @option hash [Integer] :vector_length length of the vector of Int. By default 1.
    # @option hash [Integer] :signed specifies if the Int is signed or not. By default {BOAST.get_default_int_signed}.
    def initialize(hash={})
      if hash[:size] then
        @size = hash[:size]
      else
        @size = get_default_int_size
      end
      if hash[:signed] != nil then
        @signed = hash[:signed]
      else
        @signed = get_default_int_signed
      end
      @vector_length = hash[:vector_length]
      if @vector_length
        @total_size = @size*@vector_length
      else
        @total_size = @size
      end
    end

    def to_hash
      return { :size => @size, :vector_length => @vector_length, :signed => @signed }
    end

    def copy(options={})
      hash = to_hash
      options.each { |k,v|
        hash[k] = v
      }
      return Int::new(hash)
    end

    def signed?
      return @signed
    end

    def decl
      if lang == FORTRAN then
        return "integer(kind=#{@size})" if @size
        return "integer"
      end
      if lang == C then
        if vector? && !meta_vector? then
          return get_vector_decl(self)
        else
          s = ""
          s << "u" unless @signed
          return s+"int#{8*@size}_t" if @size
          return s+"int"
        end
      else
        s =""
        unless @signed then
          s << "u"
          s << "nsigned " if lang == CUDA && !@vector_length
	  s << "nsigned " if lang == HIP && !@vector_length
        end
        case @size
        when 1
          s << "char"
        when 2
          s << "short"
        when 4
          s << "int"
        when 8
          if (lang == CUDA || lang == HIP)
            case @vector_length
            when 1, nil
              s << "long long"
            else
              s << "longlong"
            end
          else
            s << "long"
          end
        when nil
          s << "int"
        else
          raise "Unsupported integer size!"
        end
        if vector? then
          s << "#{@vector_length}"
        end
        return s
      end
    end

    def decl_ffi
      if lang == FORTRAN && ( @vector_length.kind_of?(Variable) || vector? )
        return :pointer
      end
      t = ""
      t << "u" unless @signed
      t << "int"
      t << "#{@size*8}" if @size
      t << "x#{@vector_length}" if vector?
      return t.to_sym
    end

    def suffix
      s = ""
      return s
    end

  end

  default_state_getter :default_type,          Int, '"const_get(#{envs})"'

  # @!parse module VarFunctors; var_functorize CStruct; end
  class CStruct < DataType

    attr_reader :name, :members, :members_array

    # Creates a new structured type.
    # @param [Hash] hash named options
    # @option hash [#to_s] :type_name
    # @option hash [Array<Variable>] :members list of Variable that create the type
    def initialize(hash={})
      @name = hash[:type_name]
      @members = {}
      @members_array = []
      hash[:members].each { |m|
        mc = m.copy
        @members_array.push(mc)
        @members[mc.name] = mc
      }
    end

    def to_hash
      { type_name: @name, members: @members_array }
    end

    def decl
      return decl_c if [C, CL, CUDA, HIP].include?( lang )
      return decl_fortran if lang == FORTRAN
    end

    def define
      return define_c if [C, CL, CUDA, HIP].include?( lang )
      return define_fortran if lang == FORTRAN
    end

    private

    def decl_c
      return "struct #{@name}" if [C, CL, CUDA, HIP].include?( lang )
    end

    def decl_fortran
      return "TYPE(#{@name})" if lang == FORTRAN
    end

    def define_c
      s = indent
      s << decl_c + " {"
      output.puts s
      increment_indent_level
      @members_array.each { |value|
         value.decl
      }
      decrement_indent_level
      s = indent
      s << "}"
      s << finalize
      output.print s
      return self
    end
    
    def define_fortran
      s = indent
      s << "TYPE :: #{@name}\n"
      output.puts s
      increment_indent_level
      @members_array.each { |value|
         value.decl
      }
      decrement_indent_level
      s = indent
      s << "END TYPE #{@name}"
      s << finalize
      output.print s
      return self
    end

    def finalize
       s = ""
       s << ";" if [C, CL, CUDA, HIP].include?( lang )
       s << "\n"
       return s
    end

  end

  # @!parse module VarFunctors; var_functorize CustomType; end
  class CustomType < DataType

    attr_reader :size, :name, :vector_length
    def initialize(hash={})
      @name = hash[:type_name]
      @size = hash[:size]
      @size = 0 if @size.nil?
      @vector_length = hash[:vector_length]
      if @vector_length
        @total_size = @size*@vector_length
      else
        @total_size = @size
      end
    end

    def decl
      return "#{@name}" if [C, CL, CUDA, HIP].include?( lang )
    end

  end

end
