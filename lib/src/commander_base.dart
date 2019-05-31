import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';

import 'package:path/path.dart' as p;

typedef dynamic Callback(Map arguments);

String _camelCase(String flag) {
  return flag.split('-').reduce((v, e) {
    if (e != null && e.isNotEmpty) {
      return v + e[0].toUpperCase() + e.substring(1);
    }
  });
}

class Option {
  String short = '', long = '';
  bool required = false;
  bool optional = false;
  bool boolean = false;
  String flags = '';
  String description = '';
  dynamic defaultValue;

  String get name => long.replaceAll(RegExp('--|no-'), '');

  String get attributeName => _camelCase(name);

  bool match(String arg) => short == arg || long == arg;

  Option(String flags, [String description]) {
    this.flags = flags;
    required = flags.contains('<');
    optional = flags.contains('[');
    boolean = !flags.contains('-no-');

    var flagList = flags.split(RegExp('[ ,|]+'));
    if (flagList.length > 1 && !RegExp('^[[<]').hasMatch(flagList[1])) {
      short = flagList.removeAt(0);
    }
    long = flagList.removeAt(0);
    this.description = description ?? '';
  }
}

class Argument {
  bool required = false;
  String name = '';
  bool variadic = false;
}

class Command {
  List<Command> _commands = [];
  List<Option> _options = [];
  Map<String, bool> _execs = {};
  bool _allowUnknownOption = false;
  List<Argument> _args = [];

  String _name;
  String _alias;

  bool _executables = false;
  String _defaultExecutable;
  bool _noHelp;
  Command _parent;

  String _description;
  Map<String, String> _argsDescription;

  String _version = '';
  String _versionOptionName = '';

  String _usage;

  Command._(this._name);

  factory Command() => Command._(null);

  Command command(String command,
      {String description, bool isDefault = false, bool noHelp = false}) {
    var args = command.split(RegExp(' +'));
    var cmd = Command._(args.removeAt(0));

    if (description != null) {
      cmd.setDescription(description);
      _executables = true;
      _execs[cmd._name] = true;
      if (isDefault) {
        _defaultExecutable = cmd._name;
      }
    }
    cmd._noHelp = noHelp;
    _commands.add(cmd);
    cmd._parseExpectedArgs(args);
    cmd._parent = this;

    return cmd;
  }

  void setArguments(String arguments) =>
      _parseExpectedArgs(arguments.split(RegExp(' +')));

  _addImplicitHelpCommand() {
    command('help [cmd]', description: 'display help for [cmd]');
  }

  _parseExpectedArgs(List<String> args) {
    if (args == null || args.isEmpty) return;
    args.forEach((arg) {
      var len = arg.length;

      var argDetails = Argument();
      switch (arg[0]) {
        case '<':
          argDetails.required = true;
          argDetails.name = arg.substring(1, len - 1);
          break;
        case '[':
          argDetails.name = arg.substring(1, len - 1);
          break;
      }

      len = argDetails.name.length;
      if (len > 3 && argDetails.name.endsWith('...')) {
        argDetails.variadic = true;
        argDetails.name = argDetails.name.substring(0, len - 3);
      }
      if (argDetails.name != '') {
        _args.add(argDetails);
      }
    });
  }

  void setAction(Callback fn) {
    listener(Map arguments) {
      Map fnArgs = {};
      List args = arguments['args'] ?? [];
      List unknown = arguments['unknown'] ?? [];

      var parsed = _parseOptions(unknown);

      _outputHelpIfNecessary(this, parsed['unknown']);

      if (parsed['unknown'].isNotEmpty) {
        _unknownOption(parsed['unknown'].first);
      }

      if (parsed['args'].isNotEmpty) {
        args = parsed['args']..addAll(args);
      }

      int i = 0, argsLen = _args.length;
      _args.forEach((arg) {
        if (arg.required) {
          // required arg
          if (args.isEmpty) {
            _missingArgument(arg.name);
          } else {
            fnArgs[arg.name] = args.removeAt(0);
          }
        } else if (arg.variadic) {
          // variadic arg
          if (i != argsLen - 1) {
            _variadicArgNotLast(arg.name);
          } else {
            fnArgs[arg.name] = args;
            args = [];
          }
        } else {
          // optional arg
          if (args.isEmpty) {
            fnArgs[arg.name] = null;
          } else {
            fnArgs[arg.name] = args.removeAt(0);
          }
        }
        i++;
      });

      fn(fnArgs);
    }

    var parent = _parent ?? this;
    var name = parent == this ? '*' : _name;

    parent._setCommandCallback(name, listener);
    if (_alias != null) {
      parent._setCommandCallback(_alias, listener);
    }
  }

  int _largestOptionLength() {
    var options = [..._options];
    options.add(Option('-h, --help'));
    return options.map((opt) => opt.flags.length).reduce(math.max);
  }

  int _largestArgLength() {
    return _args.isEmpty
        ? 0
        : _args.map((arg) => arg.name.length).reduce(math.max);
  }

  Iterable<List<String>> _prepareCommands() {
    return _commands.where((cmd) => !cmd._noHelp).map((cmd) {
      var args = cmd._args.map((arg) => _humanReadableArgName(arg)).join(' ');

      return [
        cmd._name +
            (cmd._alias != null ? '|' + cmd._alias : '') +
            (cmd._options.isNotEmpty ? ' [options]' : '') +
            (args != '' ? ' ' + args : ''),
        cmd._description
      ];
    });
  }

  int _largestCommandLength() {
    var commands = _prepareCommands();
    return commands.isEmpty
        ? 0
        : commands.map((cmd) => cmd[0].length).reduce(math.max);
  }

  int _padWidth() {
    var width = _largestOptionLength();
    if (_argsDescription != null && _args.isNotEmpty) {
      var argLen = _largestArgLength();
      if (argLen > width) {
        width = argLen;
      }
    }
    if (_commands != null && _commands.isNotEmpty) {
      var cmdLen = _largestCommandLength();
      if (cmdLen > width) {
        width = cmdLen;
      }
    }
    return width;
  }

  String get commmandHelp {
    if (_commands.isEmpty) return null;

    var commands = _prepareCommands();
    var width = _padWidth();

    return [
      'Commands:',
      commands
          .map((cmd) {
            var desc = cmd[1] != null ? '  ' + cmd[1] : '';
            return (desc != '' ? cmd[0].padRight(width) : cmd[0]) + desc;
          })
          .join('\n')
          .replaceAll(RegExp('^', multiLine: true), '  '),
      ''
    ].join('\n');
  }

  String get optionHelp {
    var width = _padWidth();

    return (_options.map((option) {
      return option.flags.padRight(width) +
          '  ' +
          option.description +
          ((option.boolean && option.defaultValue != null)
              ? ' (default: ' + json.encode(option.defaultValue) + ')'
              : '');
    }).toList()
          ..addAll([
            '-h, --help'.padRight(width) + '  ' + 'output usage information'
          ]))
        .join('\n');
  }

  String get helpInformation {
    var desc = [];
    if (_description != null && _description != '') {
      desc = [_description, ''];
      var argsDescription = _argsDescription;
      if (argsDescription != null && _args.isNotEmpty) {
        var width = _padWidth();
        desc.add('Arguments:');
        desc.add('');
        _args.forEach((arg) {
          desc.add('  ' +
                  arg.name.padRight(width) +
                  '  ' +
                  argsDescription[arg.name] ??
              '');
        });
        desc.add('');
      }
    }

    var cmdName = _name;
    if (_alias != null) {
      cmdName += '|' + _alias;
    }

    var usage = ['Usage: ' + cmdName + ' ' + this.usage, ''];

    var cmds = [];
    var commandHelp = this.commmandHelp;
    if (commandHelp != null) cmds = [commandHelp];

    var options = [
      'Options:',
      '' + optionHelp.replaceAll(RegExp('^', multiLine: true), '  '),
      ''
    ];

    return [...usage, ...desc, ...options, ...cmds].join('\n');
  }

  _outputHelp() {
    print(helpInformation);
    _invokeCallback('--help');
  }

  _outputHelpIfNecessary(Command cmd, List options) {
    options ??= [];
    for (var i = 0; i < options.length; i++) {
      if (options[i] == '--help' || options[i] == '-h') {
        cmd._outputHelp();
        exit(0);
      }
    }
  }

  Option _optionFor(String arg) =>
      _options.firstWhere((opt) => opt.match(arg), orElse: () => null);

  Map<String, List<Callback>> _callbacks = {};

  void on(String key, Callback fn) => _setCallback(key, fn);

  void _setCallback(String key, Callback fn) {
    if (!_callbacks.containsKey(key)) {
      _callbacks[key] = [fn];
    } else {
      _callbacks[key].add(fn);
    }
  }

  void _invokeCallback(String key, [Map fnArgs]) {
    var fnList = _callbacks[key];
    if (fnList != null) {
      fnList.forEach((fn) => fn(fnArgs));
    }
  }

  void _setOptionCallback(String option, Callback fn) {
    _setCallback('option:' + option, fn);
  }

  void _setOptionValue(String option, String value) {
    _invokeCallback('option:' + option, {'arg': value});
  }

  void _setCommandCallback(String command, Callback fn) {
    _setCallback('command:' + command, fn);
  }

  bool _hasCommandCallback(String command) =>
      _callbacks.containsKey('command:' + command);

  void _invokeCommandCallback(String command, Map args) {
    _invokeCallback('command:' + command, args);
  }

  Map<String, dynamic> _internalMap = {};

  operator []=(String name, dynamic value) {
    _internalMap[name] = value;
  }

  operator [](String name) => _internalMap[name];

  void option(String flags, String description,
      {Callback fn, dynamic defaultValue}) {
    var option = Option(flags, description);
    var oname = option.name;
    var name = option.attributeName;

    if (!option.boolean || option.optional || option.required) {
      if (!option.boolean) defaultValue = true;
      if (defaultValue != null) {
        this[name] = defaultValue;
        option.defaultValue = defaultValue;
      }
    }

    _options.add(option);
    _setOptionCallback(oname, (args) {
      var val;
      if (args != null && fn != null) {
        val = fn(
            {...args, 'value': this[name] == null ? defaultValue : this[name]});
      }
      if (this[name] is bool || this[name] == null) {
        if (val == null) {
          this[name] = option.boolean ? defaultValue ?? true : false;
        } else {
          this[name] = val;
        }
      } else if (val != null) {
        this[name] = val;
      }
    });
  }

  Map opts() {
    var result = {}, len = _options.length;

    for (var i = 0; i < len; i++) {
      var key = _options[i].attributeName;
      result[key] = key == _versionOptionName ? _version : this[key];
    }

    return result;
  }

  Map<String, List> _parseOptions(List argv) {
    var args = [], unknownOptions = [];
    var len = argv.length;
    bool literal = false;
    String arg;
    Option option;

    for (var i = 0; i < len; i++) {
      arg = argv[i];

      if (literal) {
        args.add(arg);
        continue;
      }

      if (arg == '--') {
        literal = true;
        continue;
      }

      option = _optionFor(arg);

      if (option != null) {
        if (option.required) {
          // requires arg
          if (++i >= len || (arg = argv[i]) == null) {
            return _optionMissingArgument(option);
          }
          _setOptionValue(option.name, arg);
        } else if (option.optional) {
          // optional arg
          if (i + 1 >= len) {
            arg = null;
          } else {
            arg = argv[i + 1];
            if (arg == null || (arg[0] == '-' && arg != '-')) {
              arg = null;
            } else {
              ++i;
            }
          }
          _setOptionValue(option.name, arg);
        } else {
          // bool
          _setOptionValue(option.name, null);
        }
        continue;
      }

      // looks like an option
      if (arg.isNotEmpty && arg[0] == '-') {
        unknownOptions.add(arg);

        // If the next argument looks like it might be
        // an argument for this option, we pass it on.
        // If it isn't, then it'll simply be ignored
        if (i + 1 < len && argv[i + 1][0] != '-') {
          unknownOptions.add(argv[++i]);
        }
        continue;
      }

      // arg
      args.add(arg);
    }

    return {'args': args, 'unknown': unknownOptions};
  }

  void _parseArgs(List args, List unknown) {
    String name;

    if (args.isNotEmpty) {
      name = args[0];
      if (_hasCommandCallback(name)) {
        _invokeCommandCallback(name, {'args': args.sublist(1), 'unknown': unknown});
      } else {
        _invokeCommandCallback('*', {'args': args});
      }
    } else {
      _outputHelpIfNecessary(this, unknown);

      if (unknown.isNotEmpty) {
        _unknownOption(unknown[0]);
      }
      if (_commands.isEmpty && _args.any((a) => !a.required)) {
        _invokeCommandCallback('*', {});
      }
    }
  }

  void setVersion(String version, [String flags]) {
    _version = version;
    flags ??= '-V, --version';
    var versionOption = Option(flags, 'output the version number');
    if (versionOption.long.length > 2) {
      _versionOptionName = versionOption.long.substring(2);
    } else {
      _versionOptionName = 'version';
    }
    _options.add(versionOption);
    _setOptionCallback(_versionOptionName, (args) {
      print(version);
      exit(0);
    });
  }

  String get version => _version;

  void setDescription(String descr, [Map<String, String> argsDescr]) {
    _description = descr;
    _argsDescription = argsDescr;
  }

  String get description => _description;

  void setAlias(String alias) {
    var command = this;
    if (_commands.isNotEmpty) {
      command = _commands[_commands.length - 1];
    }
    if (alias == command._name) {
      throw 'Command alias can\'t be the same as its name';
    }
    command._alias = alias;
  }

  String get alias {
    var command = this;
    if (_commands.isNotEmpty) {
      command = _commands[_commands.length - 1];
    }
    return command._alias;
  }

  String _humanReadableArgName(Argument arg) {
    var nameOutput = arg.name + (arg.variadic ? '...' : '');

    return arg.required ? '<' + nameOutput + '>' : '[' + nameOutput + ']';
  }

  void setUsage(String usage) => _usage = usage;

  String get usage {
    var args = _args.map((arg) => _humanReadableArgName(arg));

    var usage = '[options]' +
        (_commands.isNotEmpty ? '[command]' : '') +
        (args.isNotEmpty ? ' ' + args.join(' ') : '');

    return _usage ?? usage;
  }

  void setName(String name) => _name = name;

  String get name => _name;

  _missingArgument(String name) {
    print("error: missing required argument `$name'");
    exit(1);
  }

  _optionMissingArgument(Option option, [String flag]) {
    if (flag != null) {
      print("error: option `${option.flags}' argument missing, got `$flag'");
    } else {
      print("error: option `${option.flags}' argument missing");
    }
    exit(1);
  }

  _unknownOption(String flag) {
    if (_allowUnknownOption) return;
    print("error: unknown option `$flag'");
    exit(1);
  }

  _variadicArgNotLast(String name) {
    print("error: variadic arguments must be last `$name'");
    exit(1);
  }

  List<String> _normalize(List<String> argv) {
    var ret = <String>[];
    String arg;
    int index;
    Option lastOpt;

    for (var i = 0, len = argv.length; i < len; i++) {
      arg = argv[i];
      if (i > 0) {
        lastOpt = _optionFor(argv[i - 1]);
      }

      if (arg == '--') {
        ret.addAll(argv.sublist(i));
        break;
      } else if (lastOpt != null && lastOpt.required) {
        ret.add(arg);
      } else if (arg.length > 1 && arg[0] == '-' && arg[1] != '-') {
        arg.substring(1).split('').forEach((c) => ret.add('-' + c));
      } else if (arg.startsWith('--') && (index = arg.indexOf('=')) != -1) {
        ret.add(arg.substring(0, index));
        ret.add(arg.substring(index + 1));
      } else {
        ret.add(arg);
      }
    }

    return ret;
  }

  void parse(List<String> argv) {
    if (_executables) _addImplicitHelpCommand();

    _name ??= p.basenameWithoutExtension(Platform.script.path);

    if (_executables && _defaultExecutable == null && argv.isEmpty) {
      argv.add('--help');
    }

    var parsed = _parseOptions(_normalize(argv));
    var args = parsed['args'];

    _parseArgs(args, parsed['unknown']);
  }
}
