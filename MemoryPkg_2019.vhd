--
--  File Name:         MemoryPkg_2019.vhd
--  Design Unit Name:  MemoryPkg_2019
--  Revision:          STANDARD VERSION
--
--  Maintainer:        Jim Lewis      email:  jim@synthworks.com 
--  Contributor(s):            
--     Jim Lewis      email:  jim@synthworks.com   
--
--  Description
--      Package defines a protected type, MemoryPType, and methods  
--      for efficiently implementing memory data structures
--    
--  Developed for: 
--        SynthWorks Design Inc. 
--        VHDL Training Classes
--        11898 SW 128th Ave.  Tigard, Or  97223
--        http://www.SynthWorks.com
--
--  Revision History:
--    Date      Version    Description
--    05/2005   0.1        Initial revision
--    06/2015   2015.06    Updated for Alerts, ...
--                         Numerous revisions for VHDL Testbenches and Verification
--    01/2016   2016.01    Update for buf.all(buf'left)
--    11/2016   2016.11    Refinement to MemRead to return value, X (if X), U (if not initialized)
--    01/2020   2020.01    Updated Licenses to Apache
--    12/2020   2020.12    Beta version of MemoryPType with VHDL-2019 generics.
--                         Used in place of MemoryPkg.  Tested in RivieraPro.  
--
--
--  This file is part of OSVVM.
--  
--  Copyright (c) 2005 - 2020 by SynthWorks Design Inc.  
--  
--  Licensed under the Apache License, Version 2.0 (the "License");
--  you may not use this file except in compliance with the License.
--  You may obtain a copy of the License at
--  
--      https://www.apache.org/licenses/LICENSE-2.0
--  
--  Unless required by applicable law or agreed to in writing, software
--  distributed under the License is distributed on an "AS IS" BASIS,
--  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--  See the License for the specific language governing permissions and
--  limitations under the License.
--  

use std.textio.all ;
library IEEE ; 
  use IEEE.std_logic_1164.all ; 
  use IEEE.numeric_std.all ; 
  use IEEE.numeric_std_unsigned.all ; 
  use IEEE.math_real.all ;
  
use work.TextUtilPkg.all ;
use work.TranscriptPkg.all ;  
use work.AlertLogPkg.all ;

package MemoryPkg_2019 is
  type MemoryPType is protected 
    generic (
      constant AddrWidth : integer ;
      constant DataWidth : integer   
    ) ; 
    ------------------------------------------------------------
    procedure MemWrite ( Addr, Data  : in  std_logic_vector ) ; 

    ------------------------------------------------------------
    procedure MemRead (  
      Addr  : in  std_logic_vector ;
      Data  : out std_logic_vector 
    ) ; 
    impure function MemRead ( Addr  : std_logic_vector ) return std_logic_vector ; 

    ------------------------------------------------------------
    procedure MemErase ; 
    procedure deallocate ; 
    
    ------------------------------------------------------------
    procedure SetAlertLogID (A : AlertLogIDType) ;
    procedure SetAlertLogID (Name : string ; ParentID : AlertLogIDType := ALERTLOG_BASE_ID ; CreateHierarchy : Boolean := TRUE) ;    
    impure function GetAlertLogID return AlertLogIDType ;
    
    ------------------------------------------------------------
    procedure FileReadH (    -- Hexadecimal File Read 
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) ;
    procedure FileReadH (FileName : string ;  StartAddr : std_logic_vector) ;
    procedure FileReadH (FileName : string) ; 

    ------------------------------------------------------------
    procedure FileReadB (    -- Binary File Read 
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) ;
    procedure FileReadB (FileName : string ;  StartAddr : std_logic_vector) ;
    procedure FileReadB (FileName : string) ; 

    ------------------------------------------------------------
    procedure FileWriteH (    -- Hexadecimal File Write 
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) ;
    procedure FileWriteH (FileName : string ;  StartAddr : std_logic_vector) ;
    procedure FileWriteH (FileName : string) ; 

    ------------------------------------------------------------
    procedure FileWriteB (    -- Binary File Write 
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) ;
    procedure FileWriteB (FileName : string ;  StartAddr : std_logic_vector) ;
    procedure FileWriteB (FileName : string) ; 

  end protected MemoryPType ;

end MemoryPkg_2019 ;

package body MemoryPkg_2019 is 
  constant BLOCK_WIDTH : integer := 10 ; 

  type MemoryPType is protected body

    type MemBlockType    is array (integer range <>) of integer ;
    type MemBlockPtrType is access MemBlockType ;
    type MemArrayType    is array (integer range <>) of MemBlockPtrType ;
    type ArrayPtrVarType is access MemArrayType ; 

--!!    variable ArrayPtrVar     : ArrayPtrVarType := NULL ; 
--!!    variable AddrWidthVar    : integer := -1 ;  -- set by MemInit - merges addr length and initialized checks.
--!!    variable DataWidthVar    : natural := 1 ;   -- set by MemInit
--!!    variable BlockkWidthVar  : natural := 0 ;   -- set by MemInit
    
--!!
--!! TODO:  AddrWidthVar f(AddrWidth, DataWidth)
--!! TODO:  DataWidthVar f(DataWidth mod 16)
--!!
    variable DataWidthVar    : natural := DataWidth ;  -- set by Generic
    variable AddrWidthVar    : integer := AddrWidth ;  -- set by Generic 
    variable BlockkWidthVar  : natural := minimum(BLOCK_WIDTH, AddrWidth) ;   -- set by Generic
    variable ArrayPtrVar     : ArrayPtrVarType := new MemArrayType(0 to 2**(AddrWidth-BlockkWidthVar)-1) ; 

    variable AlertLogIDVar : AlertLogIDType := OSVVM_ALERTLOG_ID ;
    
    type FileFormatType is (BINARY, HEX) ; 
    
    ------------------------------------------------------------
    procedure MemWrite (  Addr, Data  : in  std_logic_vector ) is 
    ------------------------------------------------------------
      variable BlockAddr, WordAddr  : integer ;
      alias aAddr : std_logic_vector (Addr'length-1 downto 0) is Addr ; 
    begin
    
      -- Check Bounds of Address and if memory is initialized
      if Addr'length /= AddrWidthVar then
        if (ArrayPtrVar = NULL) then 
          Alert(AlertLogIDVar, "MemoryPType.MemWrite:  Memory not initialized, Write Ignored.", FAILURE) ; 
        else
          Alert(AlertLogIDVar, "MemoryPType.MemWrite:  Addr'length: " & to_string(Addr'length) & " /= Memory Address Width: " & to_string(AddrWidthVar), FAILURE) ; 
        end if ; 
        return ; 
      end if ; 
      
      -- Check Bounds on Data
      if Data'length /= DataWidthVar then
        Alert(AlertLogIDVar, "MemoryPType.MemWrite:  Data'length: " & to_string(Data'length) & " /= Memory Data Width: " & to_string(DataWidthVar), FAILURE) ; 
        return ; 
      end if ; 

      if is_X( Addr ) then
        Alert(AlertLogIDVar, "MemoryPType.MemWrite:  Address X, Write Ignored.") ; 
        return ;
      end if ; 

      -- Slice out upper address to form block address
      if aAddr'high >= BlockkWidthVar then
        BlockAddr := to_integer(aAddr(aAddr'high downto BlockkWidthVar)) ;
      else
        BlockAddr  := 0 ; 
      end if ; 

      -- If empty, allocate a memory block
      if (ArrayPtrVar(BlockAddr) = NULL) then 
          ArrayPtrVar(BlockAddr) := new MemBlockType(0 to 2**BlockkWidthVar-1) ;
      end if ; 

      -- Address of a word within a block
      WordAddr  := to_integer(aAddr(BlockkWidthVar -1 downto 0)) ;

      -- Write to BlockAddr, WordAddr
      if (Is_X(Data)) then 
        ArrayPtrVar(BlockAddr)(WordAddr) := -1 ;
      else
        ArrayPtrVar(BlockAddr)(WordAddr) := to_integer( Data ) ;
      end if ;
    end procedure MemWrite ; 

    ------------------------------------------------------------
    procedure MemRead (  
    ------------------------------------------------------------
      Addr  : In   std_logic_vector ;
      Data  : Out  std_logic_vector 
    ) is
      variable BlockAddr, WordAddr  : integer ;
      alias aAddr : std_logic_vector (Addr'length-1 downto 0) is Addr ; 
    begin
      -- Check Bounds of Address and if memory is initialized
      if Addr'length /= AddrWidthVar then
        if (ArrayPtrVar = NULL) then 
          Alert(AlertLogIDVar, "MemoryPType.MemRead:  Memory not initialized. Returning U", FAILURE) ; 
        else
          Alert(AlertLogIDVar, "MemoryPType.MemRead:  Addr'length: " & to_string(Addr'length) & " /= Memory Address Width: " & to_string(AddrWidthVar), FAILURE) ; 
        end if ; 
        Data := (Data'range => 'U') ; 
        return ; 
      end if ; 
      
      -- Check Bounds on Data
      if Data'length /= DataWidthVar then
        Alert(AlertLogIDVar, "MemoryPType.MemRead:  Data'length: " & to_string(Data'length) & " /= Memory Data Width: " & to_string(DataWidthVar), FAILURE) ; 
        Data := (Data'range => 'U') ; 
        return ; 
      end if ; 

      -- If Addr X, data = X
      if is_X( aAddr ) then
        Data := (Data'range => 'X') ; 
        return ; 
      end if ; 

      -- Slice out upper address to form block address
      if aAddr'high >= BlockkWidthVar then
        BlockAddr := to_integer(aAddr(aAddr'high downto BlockkWidthVar)) ;
      else
        BlockAddr  := 0 ; 
      end if ; 
      
      -- Empty Block, return all U
      if (ArrayPtrVar(BlockAddr) = NULL) then 
        Data := (Data'range => 'U') ; 
        return ; 
      end if ; 

      -- Address of a word within a block
      WordAddr := to_integer(aAddr(BlockkWidthVar -1 downto 0)) ;

      if ArrayPtrVar(BlockAddr)(WordAddr) >= 0 then 
        -- Get the Word from the Array
        Data := to_slv(ArrayPtrVar(BlockAddr)(WordAddr), Data'length) ;

      elsif ArrayPtrVar(BlockAddr)(WordAddr) = -1 then 
       -- X in Word, return all X
        Data := (Data'range => 'X') ;

      else 
       -- Location Uninitialized, return all X
        Data := (Data'range => 'U') ;

      end if ;
    end procedure MemRead ; 

    ------------------------------------------------------------
    impure function MemRead ( Addr  : std_logic_vector ) return std_logic_vector is
    ------------------------------------------------------------
      variable BlockAddr, WordAddr  : integer ;
      alias    aAddr : std_logic_vector (Addr'length-1 downto 0) is Addr ; 
      variable Data  : std_logic_vector(DataWidthVar-1 downto 0) ; 
    begin
      MemRead(Addr, Data) ; 
      return Data ; 
    end function MemRead ; 

    ------------------------------------------------------------
    procedure MemErase is 
    -- Deallocate the memory, but not the array of pointers
    ------------------------------------------------------------
    begin
      for BlockAddr in ArrayPtrVar'range loop 
        if (ArrayPtrVar(BlockAddr) /= NULL) then 
          deallocate (ArrayPtrVar(BlockAddr)) ; 
        end if ; 
      end loop ; 
    end procedure ; 
    
    ------------------------------------------------------------
    procedure deallocate is 
    -- Deallocate all allocated memory
    ------------------------------------------------------------
    begin
      MemErase ; 
      deallocate(ArrayPtrVar) ; 
      AddrWidthVar   := -1 ;
      DataWidthVar   := 1 ;
      BlockkWidthVar  := 0 ;
    end procedure ; 

    ------------------------------------------------------------
    procedure SetAlertLogID (A : AlertLogIDType) is
    ------------------------------------------------------------
    begin
      AlertLogIDVar := A ;
    end procedure SetAlertLogID ;

    ------------------------------------------------------------
    procedure SetAlertLogID(Name : string ; ParentID : AlertLogIDType := ALERTLOG_BASE_ID ; CreateHierarchy : Boolean := TRUE) is
    ------------------------------------------------------------
    begin
      AlertLogIDVar := GetAlertLogID(Name, ParentID, CreateHierarchy) ;
    end procedure SetAlertLogID ;
    
    ------------------------------------------------------------
    impure function GetAlertLogID return AlertLogIDType is
    ------------------------------------------------------------
    begin
      return AlertLogIDVar ; 
    end function GetAlertLogID ;
    
    ------------------------------------------------------------
    -- PT Local
    procedure FileReadX (
    -- Hexadecimal or Binary File Read 
    ------------------------------------------------------------
      FileName     : string ;
      DataFormat   : FileFormatType ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) is
      -- Format:  
      --  @hh..h     -- Address in hex
      --  hhh_XX_ZZ  -- data values in hex - space delimited 
      --  "--" or "//" -- comments
     file MemFile : text open READ_MODE is FileName ;

      variable Addr             : std_logic_vector(AddrWidthVar - 1 downto 0) ;
      variable SmallAddr        : std_logic_vector(AddrWidthVar - 1 downto 0) ;
      variable BigAddr          : std_logic_vector(AddrWidthVar - 1 downto 0) ;
      variable Data             : std_logic_vector(DataWidthVar - 1 downto 0) ;
      variable LineNum          : natural ; 
      variable ItemNum          : natural ; 
      variable AddrInc          : std_logic_vector(AddrWidthVar - 1 downto 0) ; 
      variable buf              : line ;
      variable ReadValid        : boolean ;
      variable Empty            : boolean ; 
      variable MultiLineComment : boolean ; 
      variable NextChar         : character ; 
      variable StrLen           : integer ; 
    begin
      MultiLineComment := FALSE ; 
      if StartAddr'length /= AddrWidthVar and EndAddr'length /= AddrWidthVar then
        if (ArrayPtrVar = NULL) then 
          Alert(AlertLogIDVar, "MemoryPType.FileReadX:  Memory not initialized, FileRead Ignored.", FAILURE) ; 
        else
          Alert(AlertLogIDVar, "MemoryPType.FileReadX:  Addr'length: " & to_string(Addr'length) & " /= Memory Address Width: " & to_string(AddrWidthVar), FAILURE) ; 
        end if ; 
        return ; 
      end if ; 

      Addr    := StartAddr ; 
      LineNum := 0 ; 
      
      if StartAddr <= EndAddr then 
        SmallAddr := StartAddr ; 
        BigAddr   := EndAddr ; 
        AddrInc   := (AddrWidthVar -1 downto 0 => '0') + 1 ;  
      else
        SmallAddr := EndAddr ; 
        BigAddr   := StartAddr ; 
        AddrInc   := (others => '1') ;  -- -1
      end if; 
      
      ReadLineLoop : while not EndFile(MemFile) loop
        ReadLine(MemFile, buf) ;
        LineNum := LineNum + 1 ; 
        ItemNum := 0 ; 
        
        ItemLoop : loop 
          EmptyOrCommentLine(buf, Empty, MultiLineComment) ; 
          exit ItemLoop when Empty ; 
          ItemNum := ItemNum + 1 ; 
          NextChar := buf.all(buf'left) ;
          
          if (NextChar = '@') then 
          -- Get Address
            read(buf, NextChar) ; 
            ReadHexToken(buf, Addr, StrLen) ; 
            exit ReadLineLoop when AlertIf(AlertLogIDVar, StrLen = 0, "MemoryPType.FileReadX: Address length 0 on line: " & to_string(LineNum), FAILURE) ;
            exit ItemLoop when AlertIf(AlertLogIDVar, Addr < SmallAddr, 
                                           "MemoryPType.FileReadX: Address in file: " & to_hstring(Addr) & 
                                           " < StartAddr: " & to_hstring(StartAddr) & " on line: " & to_string(LineNum)) ; 
            exit ItemLoop when AlertIf(AlertLogIDVar, Addr > BigAddr, 
                                           "MemoryPType.FileReadX: Address in file: " & to_hstring(Addr) & 
                                           " > EndAddr: " & to_hstring(BigAddr) & " on line: " & to_string(LineNum)) ; 
          
          elsif DataFormat = HEX and ishex(NextChar) then 
          -- Get Hex Data
            ReadHexToken(buf, data, StrLen) ;
            exit ReadLineLoop when AlertIfNot(AlertLogIDVar, StrLen > 0, 
              "MemoryPType.FileReadH: Error while reading data on line: " & to_string(LineNum) &
              "  Item number: " & to_string(ItemNum), FAILURE) ;
            log("MemoryPType.FileReadX:  MemWrite(Addr => " & to_hstring(Addr) & ", Data => " & to_hstring(Data) & ")", DEBUG) ; 
            MemWrite(Addr, data) ; 
            Addr := Addr + AddrInc ; 
            
          elsif DataFormat = BINARY and isstd_logic(NextChar) then 
          -- Get Binary Data
            -- read(buf, data, ReadValid) ;
            ReadBinaryToken(buf, data, StrLen) ;
            -- exit ReadLineLoop when AlertIfNot(AlertLogIDVar, ReadValid, 
            exit ReadLineLoop when AlertIfNot(AlertLogIDVar, StrLen > 0, 
              "MemoryPType.FileReadB: Error while reading data on line: " & to_string(LineNum) &
              "  Item number: " & to_string(ItemNum), FAILURE) ;
            log("MemoryPType.FileReadX:  MemWrite(Addr => " & to_hstring(Addr) & ", Data => " & to_string(Data) & ")", DEBUG) ; 
            MemWrite(Addr, data) ; 
            Addr := Addr + AddrInc ; 
          
          else
          -- Invalid Text, Issue Warning and skip it
            Alert(AlertLogIDVar,  
              "MemoryPType.FileReadX: Invalid text on line: " & to_string(LineNum) &
              "  Item: " & to_string(ItemNum) & ".  Skipping text: " & buf.all) ;
            exit ItemLoop ; 
          end if ; 
          
        end loop ItemLoop ; 
      end loop ReadLineLoop ; 
      
--      -- must read EndAddr-StartAddr number of words if both start and end specified
--      if (StartAddr /= 0 or (not EndAddr) /= 0) and (Addr /= EndAddr) then 
--        Alert("MemoryPType.FileReadH: insufficient data values", WARNING) ; 
--      end if ;       
      file_close(MemFile) ; 
    end FileReadX ;
    
    ------------------------------------------------------------
    procedure FileReadH (
    -- Hexadecimal File Read 
    ------------------------------------------------------------
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) is
    begin
      FileReadX(FileName, HEX, StartAddr, EndAddr) ; 
    end FileReadH ;
    
    ------------------------------------------------------------
    procedure FileReadH (FileName : string ;  StartAddr : std_logic_vector) is
    -- Hexadecimal File Read 
    ------------------------------------------------------------
      constant EndAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileReadX(FileName, HEX, StartAddr, EndAddr) ; 
    end FileReadH ;

    ------------------------------------------------------------
    procedure FileReadH (FileName : string) is 
    -- Hexadecimal File Read 
    ------------------------------------------------------------
      constant StartAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '0') ;
      constant EndAddr   : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileReadX(FileName, HEX, StartAddr, EndAddr) ; 
    end FileReadH ;    
    
     ------------------------------------------------------------
    procedure FileReadB (
    -- Binary File Read 
    ------------------------------------------------------------
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) is
    begin
      FileReadX(FileName, BINARY, StartAddr, EndAddr) ; 
    end FileReadB ;
    
    ------------------------------------------------------------
    procedure FileReadB (FileName : string ;  StartAddr : std_logic_vector) is
    -- Binary File Read 
    ------------------------------------------------------------
      constant EndAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileReadX(FileName, BINARY, StartAddr, EndAddr) ; 
    end FileReadB ;

    ------------------------------------------------------------
    procedure FileReadB (FileName : string) is 
    -- Binary File Read 
    ------------------------------------------------------------
      constant StartAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '0') ;
      constant EndAddr   : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileReadX(FileName, BINARY, StartAddr, EndAddr) ; 
    end FileReadB ;    

    ------------------------------------------------------------
    -- PT Local
    procedure FileWriteX (
    -- Hexadecimal or Binary File Write 
    ------------------------------------------------------------
      FileName     : string ; 
      DataFormat   : FileFormatType ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) is
      -- Format:  
      --  @hh..h     -- Address in hex
      --  hhhhh      -- data one per line in either hex or binary as specified 
      file MemFile : text open WRITE_MODE is FileName ;
      alias normStartAddr     : std_logic_vector(StartAddr'length-1 downto 0) is StartAddr ; 
      alias normEndAddr       : std_logic_vector(EndAddr'length-1 downto 0) is EndAddr ; 
      variable StartBlockAddr : natural ;
      variable EndBlockAddr   : natural ;
      variable StartWordAddr  : natural ; 
      variable EndWordAddr    : natural ; 
      variable Data           : std_logic_vector(DataWidthVar - 1 downto 0) ;
      variable FoundData      : boolean ; 
      variable buf            : line ;
    begin
      if StartAddr'length /= AddrWidthVar and EndAddr'length /= AddrWidthVar then
      -- Check StartAddr and EndAddr Widths and Memory not initialized
        if (ArrayPtrVar = NULL) then 
          Alert(AlertLogIDVar, "MemoryPType.FileWriteX:  Memory not initialized, FileRead Ignored.", FAILURE) ; 
        else
          AlertIf(AlertLogIDVar, StartAddr'length /= AddrWidthVar, "MemoryPType.FileWriteX:  StartAddr'length: " 
                               & to_string(StartAddr'length) & 
                               " /= Memory Address Width: " & to_string(AddrWidthVar), FAILURE) ; 
          AlertIf(AlertLogIDVar, EndAddr'length /= AddrWidthVar, "MemoryPType.FileWriteX:  EndAddr'length: " 
                               & to_string(EndAddr'length) & 
                               " /= Memory Address Width: " & to_string(AddrWidthVar), FAILURE) ; 
        end if ; 
        return ; 
      end if ; 

      if StartAddr > EndAddr then 
      -- Only support ascending addresses
        Alert(AlertLogIDVar, "MemoryPType.FileWriteX:  StartAddr: " & to_hstring(StartAddr) & 
                             " > EndAddr: " & to_hstring(EndAddr), FAILURE) ;
        return ; 
      end if ; 
            
      -- Slice out upper address to form block address
      if AddrWidthVar >= BlockkWidthVar then
        StartBlockAddr := to_integer(normStartAddr(AddrWidthVar-1 downto BlockkWidthVar)) ;
        EndBlockAddr   := to_integer(  normEndAddr(AddrWidthVar-1 downto BlockkWidthVar)) ;
      else
        StartBlockAddr  := 0 ; 
        EndBlockAddr  := 0 ; 
      end if ; 
            
      BlockAddrLoop : for BlockAddr in StartBlockAddr to EndBlockAddr loop 
        next BlockAddrLoop when ArrayPtrVar(BlockAddr) = NULL ;  
        if BlockAddr = StartBlockAddr then 
          StartWordAddr := to_integer(normStartAddr(BlockkWidthVar-1 downto 0)) ; 
        else
          StartWordAddr := 0 ;
        end if ; 
        if BlockAddr = EndBlockAddr then 
          EndWordAddr := to_integer(normEndAddr(BlockkWidthVar-1 downto 0)) ; 
        else 
          EndWordAddr := 2**BlockkWidthVar-1 ;
        end if ; 
        FoundData := FALSE ; 
        WordAddrLoop : for WordAddr in StartWordAddr to EndWordAddr loop 
          if (ArrayPtrVar(BlockAddr)(WordAddr) < 0) then 
            -- X in Word, return all X
            Data := (Data'range => 'X') ;
            FoundData := FALSE ;
          else 
            -- Get the Word from the Array
            Data := to_slv(ArrayPtrVar(BlockAddr)(WordAddr), Data'length) ;
            if not FoundData then
              -- Write Address
              write(buf, '@') ; 
              hwrite(buf, to_slv(BlockAddr, AddrWidthVar-BlockkWidthVar) & to_slv(WordAddr, BlockkWidthVar)) ; 
              writeline(MemFile, buf) ; 
            end if ; 
            FoundData := TRUE ; 
          end if ;
          if FoundData then  -- Write Data
            if DataFormat = HEX then
              hwrite(buf, Data) ; 
              writeline(MemFile, buf) ; 
            else
              write(buf, Data) ; 
              writeline(MemFile, buf) ; 
            end if; 
          end if ;                
        end loop WordAddrLoop ; 
      end loop BlockAddrLoop ;       
      file_close(MemFile) ; 
    end FileWriteX ;
    
    ------------------------------------------------------------
    procedure FileWriteH (
    -- Hexadecimal File Write 
    ------------------------------------------------------------
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) is
    begin
      FileWriteX(FileName, HEX, StartAddr, EndAddr) ; 
    end FileWriteH ;
    
    ------------------------------------------------------------
    procedure FileWriteH (FileName : string ;  StartAddr : std_logic_vector) is
    -- Hexadecimal File Write 
    ------------------------------------------------------------
      constant EndAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileWriteX(FileName, HEX, StartAddr, EndAddr) ; 
    end FileWriteH ;

    ------------------------------------------------------------
    procedure FileWriteH (FileName : string) is 
    -- Hexadecimal File Write 
    ------------------------------------------------------------
      constant StartAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '0') ;
      constant EndAddr   : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileWriteX(FileName, HEX, StartAddr, EndAddr) ; 
    end FileWriteH ;    
    
     ------------------------------------------------------------
    procedure FileWriteB (
    -- Binary File Write 
    ------------------------------------------------------------
      FileName     : string ; 
      StartAddr    : std_logic_vector ; 
      EndAddr      : std_logic_vector
    ) is
    begin
      FileWriteX(FileName, BINARY, StartAddr, EndAddr) ; 
    end FileWriteB ;
    
    ------------------------------------------------------------
    procedure FileWriteB (FileName : string ;  StartAddr : std_logic_vector) is
    -- Binary File Write 
    ------------------------------------------------------------
      constant EndAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileWriteX(FileName, BINARY, StartAddr, EndAddr) ; 
    end FileWriteB ;

    ------------------------------------------------------------
    procedure FileWriteB (FileName : string) is 
    -- Binary File Write 
    ------------------------------------------------------------
      constant StartAddr : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '0') ;
      constant EndAddr   : std_logic_vector(AddrWidthVar - 1 downto 0) := (others => '1') ;
    begin
      FileWriteX(FileName, BINARY, StartAddr, EndAddr) ; 
    end FileWriteB ;    
    
  end protected body MemoryPType ;
 
end MemoryPkg_2019 ;