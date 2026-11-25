// Small public-domain starter pack so a fresh install is useful offline.
// The songs are seeded into local SQLite on first launch and add only a few
// kilobytes to the app; there are no bundled images or audio files.

/// Bump when the starter pack changes so existing installs receive new songs.
const starterPackVersion = 2;

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
  DemoDraft(
    title: 'Simple Gifts',
    artist: 'Traditional',
    key: 'G',
    tempo: 96,
    tags: 'shaker hymn',
    body: '''
{start_of_verse: Verse 1}
'Tis the [G]gift to be simple, 'tis the [C]gift to be [G]free
'Tis the [G]gift to come down where we [D]ought to [G]be
And when we [G]find ourselves in the [C]place just [G]right
'Twill be in the [Em]valley of [D]love and de[G]light
{end_of_verse}

{start_of_verse: Verse 2}
When [G]true simplicity is [C]gained
To [G]bow and to bend we [D]shan't be a[G]shamed
To [G]turn, turn will be our de[C]light
'Til by [G]turning, turning we [D]come round [G]right
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'Down to the River to Pray',
    artist: 'Traditional',
    key: 'G',
    tempo: 84,
    tags: 'spiritual',
    body: '''
{start_of_verse: Verse 1}
As I went [G]down in the [C]river to [G]pray
Studying [G]about that [D]good old [G]way
And [G]who shall [C]wear the [G]star[Em]ry [D]crown
Good [G]Lord, show me the [C]way [D]
{end_of_verse}

{start_of_chorus: Chorus}
Oh [G]sisters, let's go [C]down
Let's go [G]down, come on [D]down
Oh [G]sisters, let's go [C]down
Down in the [G]river to [D]pray [G]
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'Wayfaring Stranger',
    artist: 'Traditional',
    key: 'Am',
    tempo: 68,
    tags: 'spiritual',
    body: '''
{start_of_verse: Verse 1}
I'm just a [Am]poor wayfaring [C]stranger
Wandering [Dm]through this world of [Am]woe
Yet there's no [Am]sickness, toil nor [C]danger
In that bright [E]land to which I [Am]go
{end_of_verse}

{start_of_chorus: Chorus}
I'm going [Am]there to see my [C]Father
I'm going [Dm]there no more to [Am]roam
I'm just a-[Am]going over [C]Jordan
I'm just a-[E]going over [Am]home
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'The Water Is Wide',
    artist: 'Traditional',
    key: 'D',
    tempo: 72,
    body: '''
{start_of_verse: Verse 1}
The [D]water is [A]wide, I can't cross [Bm]o'er
And [G]neither have I [D]wings to [A]fly
Give me a [D]boat that [A]will carry [Bm]me
And [G]both shall [D]row, my [A]love and [D]I
{end_of_verse}

{start_of_verse: Verse 2}
I [D]leaned my [A]back against an [Bm]oak
I [G]thought that [D]love would [A]surely [D]bind
But [D]love grows [A]old and [Bm]shows its [G]age
Like [D]morning [A]dew upon the [D]ground
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'Auld Lang Syne',
    artist: 'Traditional',
    key: 'G',
    tempo: 92,
    tags: 'traditional, new year',
    body: '''
{start_of_verse: Verse 1}
Should [G]old acquaintance be for[C]got, and [G]never brought to [D]mind?
Should [G]old acquaintance be for[C]got, and [G]days of [D]auld lang [G]syne?
{end_of_verse}

{start_of_chorus: Chorus}
For [G]auld lang [C]syne, my [G]dear,
For [G]auld lang [D]syne,
We'll [G]take a cup of [C]kindness [G]yet,
For [G]days of [D]auld lang [G]syne.
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'Deck the Halls',
    artist: 'Traditional',
    key: 'G',
    tempo: 120,
    tags: 'traditional, christmas',
    body: '''
{start_of_verse: Verse 1}
[G]Deck the halls with [C]boughs of [G]holly, [D]fa la la la [G]la, la la la [D]la.
[G]'Tis the season to be [C]jolly, [D]fa la la la [G]la, la la la [D]la.
{end_of_verse}

{start_of_chorus: Chorus}
[G]Don we now our [C]gay ap[G]parel, [D]fa la la la [G]la, la la la [D]la.
[G]Troll the ancient [C]Yuletide [G]carol, [D]fa la la la [G]la, la la la [G]la.
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'Jingle Bells',
    artist: 'Traditional',
    key: 'G',
    tempo: 138,
    tags: 'traditional, christmas',
    body: '''
{start_of_chorus: Chorus}
[G]Jingle bells, jingle [C]bells, jingle [G]all the [D]way!
[G]Oh what fun it is to [C]ride in a [G]one-horse [D]open [G]sleigh!
{end_of_chorus}

{start_of_verse: Verse 1}
[G]Dashing through the [C]snow in a [G]one-horse [D]open [G]sleigh,
[G]O'er the fields we [C]go, laughing [G]all the [D]way.
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'Silent Night',
    artist: 'Traditional',
    key: 'G',
    tempo: 68,
    tags: 'traditional, christmas',
    body: '''
{start_of_verse: Verse 1}
[G]Silent night, holy [D]night,
[G]All is calm, all is [D]bright.
[C]Round yon virgin, [G]mother and child,
[C]Holy infant so [D]tender and [G]mild.
{end_of_verse}

{start_of_verse: Verse 2}
[G]Silent night, holy [D]night,
[G]Shepherds quake at the [D]sight.
[C]Glories stream from [G]heaven afar,
[C]Heavenly hosts sing [D]alleluia.
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'Greensleeves',
    artist: 'Traditional',
    key: 'Am',
    tempo: 76,
    tags: 'traditional',
    body: '''
{start_of_verse: Verse 1}
[Am]Alas, my love, you [G]do me [Am]wrong,
To [C]cast me off dis[G]courteous[Am]ly.
[Am]For I have loved you [G]long, [Am]
And [C]fondly thought you [G]loved me [Am]too.
{end_of_verse}

{start_of_chorus: Chorus}
[Am]Greensleeves was all my [G]joy,
[Am]Greensleeves was my de[C]light.
[Am]Greensleeves was all my [G]joy,
And [C]who but my lady [G]Greensleeves [Am].
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'Oh! Susanna',
    artist: 'Traditional',
    key: 'G',
    tempo: 112,
    tags: 'traditional, folk',
    body: '''
{start_of_verse: Verse 1}
[G]I come from [C]Alabama with my [G]banjo on my [D]knee,
[G]I'm g’wan to [C]Louisiana my [G]true love for to [D]see.
[G]It rained all [C]night the [G]day I left, the [D]weather it was [G]dry,
[G]The sun so [C]hot I [G]sweated lots, my [D]brow was [G]very high.
{end_of_verse}

{start_of_chorus: Chorus}
[G]Oh, Susanna, [C]oh don't you [G]cry for [D]me,
[G]I come from [C]Alabama with my [G]banjo on my [D]knee.
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'This Little Light of Mine',
    artist: 'Traditional',
    key: 'G',
    tempo: 104,
    tags: 'traditional, spiritual',
    body: '''
{start_of_verse: Verse 1}
[G]This little light of [C]mine, I'm [G]gonna let it [D]shine.
[G]This little light of [C]mine, I'm [G]gonna let it [D]shine.
{end_of_verse}

{start_of_chorus: Chorus}
[G]Let it shine, let it [C]shine, let it [G]shine.
[G]Hide it under a [C]bushel? [G]No! I'm gonna let it [D]shine.
{end_of_chorus}
''',
  ),
  DemoDraft(
    title: 'When the Saints Go Marching In',
    artist: 'Traditional',
    key: 'G',
    tempo: 116,
    tags: 'traditional, jazz',
    body: '''
{start_of_verse: Verse 1}
[G]Oh, when the saints go [C]marching [G]in,
[G]Oh, when the saints go [C]marching [D]in,
[G]Oh Lord, I [C]want to be in that [G]number,
[G]When the saints go [C]marching [G]in.
{end_of_verse}
''',
  ),
  DemoDraft(
    title: 'Home! Sweet Home!',
    artist: 'Traditional',
    key: 'G',
    tempo: 76,
    tags: 'traditional, folk',
    body: '''
{start_of_verse: Verse 1}
[G]Home, home, sweet, sweet [D]home!
[G]There's no place like [C]home, [G]sweet, sweet [D]home.
[G]No matter where I [C]roam, [G]nothing can [D]e'er atone
For the [G]peace and [C]quiet of [G]my own [D]sweet [G]home.
{end_of_verse}
''',
  ),
];

/// A ready-made set list for first-run libraries, so the set lists tab has
/// something real to open instead of an empty state. Songs are matched by
/// title after seeding, the same way an imported set list is matched.
class DemoSetlistDraft {
  const DemoSetlistDraft({
    required this.title,
    required this.description,
    required this.songTitles,
  });

  final String title;
  final String description;
  final List<String> songTitles;
}

const demoSetlist = DemoSetlistDraft(
  title: 'Sunday Set',
  description: 'Four songs for a quiet morning service.',
  songTitles: [
    'Amazing Grace',
    'Simple Gifts',
    'Down to the River to Pray',
    'Wayfaring Stranger',
  ],
);
