@{
  '2.5' = @{ Dir = 'Firebird-2.5.9.27139-0_x64';        Exe = 'bin\fbserver.exe'; ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'bin\fbclient.dll'; Port = 3050 }
  '3.0' = @{ Dir = 'Firebird-3.0.14.33856-0-x64';        Exe = 'firebird.exe';     ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'fbclient.dll';     Port = 3053 }
  '4.0' = @{ Dir = 'Firebird-4.0.7.3271-0-x64';          Exe = 'firebird.exe';     ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'fbclient.dll';     Port = 3054 }
  '5.0' = @{ Dir = 'Firebird-5.0.4.1812-0-windows-x64';  Exe = 'firebird.exe';     ExeArgs = '-a'; Conf = 'firebird.conf';     Client = 'fbclient.dll';     Port = 3055 }
}
