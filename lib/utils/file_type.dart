enum FileKind { text, image, binary }

/// A dotfile with no real extension (`.gitignore`, `.bashrc`) is treated the
/// same as a name with no extension at all.
FileKind fileTypeOf(String filename) {
  final name = filename.toLowerCase();
  final dot = name.lastIndexOf('.');

  final ext = dot > 0 ? name.substring(dot + 1) : '';
  if (ext.isEmpty) return FileKind.text;

  if (_imageExts.contains(ext)) return FileKind.image;
  if (_textExts.contains(ext)) return FileKind.text;
  return FileKind.binary;
}

const _imageExts = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'bmp',
  'ico',
  'heic',
  'heif',
};

/// Extensions treated as text, grouped by category: code, config, markup,
/// styles, shell, data, plain text, and dotfiles/special names without a
/// leading dot.
const _textExts = {
  'js',
  'mjs',
  'cjs',
  'ts',
  'tsx',
  'jsx',
  'py',
  'go',
  'rs',
  'dart',
  'java',
  'kt',
  'kts',
  'c',
  'h',
  'cpp',
  'hpp',
  'cc',
  'cs',
  'swift',
  'r',
  'php',
  'rb',
  'lua',
  'scala',
  'clj',
  'ex',
  'exs',
  'json',
  'yaml',
  'yml',
  'toml',
  'ini',
  'conf',
  'cfg',
  'env',
  'properties',
  'lock',
  'editorconfig',
  'html',
  'htm',
  'xml',
  'svg',
  'md',
  'rst',
  'adoc',
  'css',
  'scss',
  'sass',
  'less',
  'sh',
  'bash',
  'zsh',
  'fish',
  'ps1',
  'bat',
  'cmd',
  'sql',
  'csv',
  'tsv',
  'txt',
  'log',
  'diff',
  'patch',
  'gitignore',
  'gitattributes',
  'dockerignore',
  'htaccess',
  'dockerfile',
  'makefile',
};
