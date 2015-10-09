module BOAST

  class Procedure
    include PrivateStateAccessor
    include Inspectable
    extend Functor

    attr_reader :name
    attr_reader :parameters
    attr_reader :constants
    attr_reader :properties
    attr_reader :headers

    def initialize(name, parameters=[], constants=[], properties={}, &block)
      @name = name
      @parameters = parameters
      @constants = constants
      @block = block
      @properties = properties
      @headers = properties[:headers]
      @headers = [] if not @headers
    end

    def boast_header_s( lang=C )
      s = ""
      headers.each { |h|
        s += "#include <#{h}>\n"
      }
      if lang == CL then
        s += "__kernel "
        wgs = @properties[:reqd_work_group_size]
        if wgs then
          s += "__attribute__((reqd_work_group_size(#{wgs[0]},#{wgs[1]},#{wgs[2]}))) "
        end
      end
      trailer = ""
      trailer += "_" if lang == FORTRAN
      trailer += "_wrapper" if lang == CUDA
      if @properties[:return] then
        s += "#{@properties[:return].type.decl} "
      elsif lang == CUDA
        s += "unsigned long long int "
      else
        s += "void "
      end
      s += "#{@name}#{trailer}("
      if parameters.first then
        s += parameters.first.boast_header(lang)
        parameters[1..-1].each { |p|
          s += ", "
          s += p.boast_header(lang)
        }
      end
      if lang == CUDA then
        s += ", " if parameters.first
        s += "size_t *block_number, size_t *block_size"
      end
      s += ")"
      return s
    end

    def boast_header(lang=C)
      s = boast_header_s(lang)
      s += ";\n"
      output.print s
      return self
    end

    def call(*parameters)
      prefix = ""
      prefix += "call " if lang==FORTRAN
      f = FuncCall::new(@name, *parameters)
      f.prefix = prefix
      return f
    end

    def close
      return close_fortran if lang==FORTRAN
      return close_c if [C, CL, CUDA].include?( lang )
    end

    def ckernel
      old_output = output
      k = CKernel::new
      k.procedure = self
      self.pr
      set_output( old_output )
      return k
    end

    def close_c
      s = ""
      s += indent + "return #{@properties[:return]};\n" if @properties[:return]
      decrement_indent_level
      s += indent + "}"
      output.puts s
      return self
    end

    def close_fortran
      s = ""
      if @properties[:return] then
        s += indent + "#{@name} = #{@properties[:return]}\n"
        decrement_indent_level
        s += indent + "END FUNCTION #{@name}"
      else
        decrement_indent_level
        s += indent + "END SUBROUTINE #{@name}"
      end
      output.puts s
      return self
    end

    def pr
      open
      if @block then
        @block.call
        close
      end
      return self
    end

    def decl
      return decl_fortran if lang==FORTRAN
      return decl_c if [C, CL, CUDA].include?( lang )
    end

    def decl_fortran
      output.puts indent + "INTERFACE"
      increment_indent_level
      open_fortran
      close_fortran
      decrement_indent_level
      output.puts indent + "END INTERFACE"
      return self
    end

    def decl_c_s
      s = ""
      if lang == CL then
        if @properties[:local] then
          s += "#if __OPENCL_C_VERSION__ && __OPENCL_C_VERSION__ >= 120\n"
          s += "static\n"
          s += "#endif\n"
        else
          s += "__kernel "
          wgs = @properties[:reqd_work_group_size]
          if wgs then
            s += "__attribute__((reqd_work_group_size(#{wgs[0]},#{wgs[1]},#{wgs[2]}))) "
          end
        end
      elsif lang == CUDA then
        if @properties[:local] then
          s += "static __device__ "
        else
          s += "__global__ "
          wgs = @properties[:reqd_work_group_size]
          if wgs then
            s += "__launch_bounds__(#{wgs[0]}*#{wgs[1]}*#{wgs[2]}) "
          end
        end
      elsif lang == C then
        if @properties[:local] then
          s += "static "
        end
        if @properties[:inline] then
          s+= "inline "
        end
      end
      if @properties[:qualifiers] then
        s += "#{@properties[:qualifiers]} "
      end
      if @properties[:return] then
        s += "#{@properties[:return].type.decl} "
      else
        s += "void "
      end
      s += "#{@name}("
      if parameters.first then
        s += parameters.first.decl_c_s(@properties[:local])
        parameters[1..-1].each { |p|
          s += ", "+p.decl_c_s(@properties[:local])
        }
      end
      s += ")"
      return s
    end

    def decl_c
      s = indent + decl_c_s + ";"
      output.puts s
      return self
    end

    def open
      return open_fortran if lang==FORTRAN
      return open_c if [C, CL, CUDA].include?( lang )
    end

    def to_s
      return decl_c_s if [C, CL, CUDA].include?( lang )
      return to_s_fortran if lang==FORTRAN
    end

    def to_s_fortran
      s = ""
      if @properties[:return] then
        s += "#{@properties[:return].type.decl} FUNCTION "
      else
        s += "SUBROUTINE "
      end
      s += "#{@name}("
      s += parameters.collect(&:name).join(", ")
      s += ")"
    end

    def pr_align
    end

    def open_c
      s = decl_c_s + "{"
      output.puts s
      increment_indent_level
      constants.each { |c|
        c.decl
      }
      if lang == C then
        parameters.each { |p|
          p.pr_align
        }
      end
      return self
    end

    def open_fortran
      s = indent + to_s_fortran
      s += "\n"
      increment_indent_level
      s += indent + "integer, parameter :: wp=kind(1.0d0)"
      output.puts s
      constants.each { |c|
        c.decl
      }
      parameters.each { |p|
        p.decl
        p.pr_align
      }
      return self
    end

  end

end
