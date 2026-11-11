/// Public-domain demo material so the app is usable on first launch.
/// `lib/core/demo/demo_songs.dart` keeps these out of the user's way until
/// they choose to load them from Settings or the empty state.
class DemoDraft {
  const DemoDraft({
    required this.title,
    required this.artist,
    required this.body,
    required this.key,
    this.capo = 0,
    this.tempo,
    this.tags = 'traditional',
  });

  final String title;
  final String artist;
  final String body;
  final String key;
  final int capo;
  final int? tempo;
  final String tags;
}

const demoDrafts = <DemoDraft>[
  DemoDraft(
    title: 'Amazing Grace',
    artist: 'Traditional',
    key: 'G',
    tempo: 72,
    body: '''
{start_of_verse: Verse 1}
[G]Amazing grace, how [G7]sweet the [C]sound
That [G]saved a wretch like [D]me
I [G]once was lost, but [G7]now am [C]found
Was [G]blind but [D]now I [G]see
{end_of_verse}

{start_of_verse: Verse 2}
[G]'Twas grace that taught my [G7]heart to [C]fear
And [G]grace my fears re[D]lieved
How [G]precious did that [G7]grace ap[C]pear
The [G]hour I [D]first be[G]lieved
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'Scarborough Fair',
    artist: 'Traditional',
    key: 'Am',
    tempo: 88,
    body: '''
{start_of_verse: Verse 1}
[Am]Are you going to [G]Scarborough [Am]Fair?
[Am]Parsley, [C]sage, rose[G]mary and [Am]thyme
Re[Am]member me [G]to one who [Am]lives there
[Am]She once [C]was a [G]true love of [Am]mine
{end_of_verse}

{start_of_verse: Verse 2}
[Am]Tell her to make me a [G]cambric [Am]shirt
[Am]Parsley, [C]sage, rose[G]mary and [Am]thyme
With[Am]out no seams nor [G]needle[Am]work
[Am]Then she'll [C]be a [G]true love of [Am]mine
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'House of the Rising Sun',
    artist: 'Traditional',
    key: 'Am',
    tempo: 76,
    body: '''
{start_of_verse: Verse 1}
[Am]There is a [C]house in [D]New Or[F]leans
They [Am]call the [C]Rising [E]Sun
And it's [Am]been the [C]ruin of [D]many a poor [F]boy
And [Am]God, I [E]know I'm [Am]one
{end_of_verse}

{start_of_chorus: Chorus}
Oh [Am]mother, [C]tell your [D]children [F]
Not to [Am]do what [C]I have [E]done
[Am]Spend your [C]lives in [D]sin and [F]misery
In the [Am]House of the [E]Rising [Am]Sun
{end_of_chorus}
''',
  ),
];
