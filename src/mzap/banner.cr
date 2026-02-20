module Mzap
  module Banner
    extend self

    def show(io : IO = STDERR) : Nil
      io.puts ""
      io.puts "          ,/"
      io.puts "        ,'/"
      io.puts "      ,' /"
      io.puts "    ,'  /_____,"
      io.puts "  .'____    ,'                     MZAP"
      io.puts "        /  ,'     [ Multiple target/agent ZAP scanning ]"
      io.puts "       / ,'       [ #{VERSION} ] [ by @hahwul ]"
      io.puts "      /,'"
      io.puts "     /'"
      io.puts ""
    end
  end
end
