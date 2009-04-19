use inc::Module::Install;

name           'Class-Entangle';
all_from       'lib/Class/Entangle.pm';

test_requires(
    'Test::More' => 0.8,
);
requires(
    'Exporter' => '5.63',
);

WriteAll;
