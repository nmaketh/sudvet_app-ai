import 'package:flutter/material.dart';

class LearnPage extends StatelessWidget {
  const LearnPage({super.key});

  @override
  Widget build(BuildContext context) {
    final guides = [
      _GuideSection(
        title: 'LSD',
        subtitle: 'Lumpy Skin Disease',
        symptoms: const ['Skin nodules', 'Fever', 'Reduced appetite', 'Lameness'],
        prevention: const [
          'Isolate affected animals quickly.',
          'Control insects and improve hygiene.',
          'Keep vaccination records updated.',
        ],
        whenToCallVet:
            'Call your veterinarian immediately when nodules spread fast or fever persists.',
      ),
      _GuideSection(
        title: 'FMD',
        subtitle: 'Foot-and-Mouth Disease',
        symptoms: const ['Mouth lesions', 'Excess salivation', 'Lameness', 'Fever'],
        prevention: const [
          'Restrict movement between herds.',
          'Disinfect feed and water stations.',
          'Follow local vaccination plans.',
        ],
        whenToCallVet:
            'Call your veterinarian for confirmation if lesions and lameness appear together.',
      ),
      _GuideSection(
        title: 'ECF',
        subtitle: 'East Coast Fever',
        symptoms: const ['High fever', 'Swollen lymph nodes', 'Loss of appetite'],
        prevention: const [
          'Strengthen tick control routines.',
          'Maintain clean resting areas.',
          'Review preventive medicine schedule with professionals.',
        ],
        whenToCallVet:
            'Call your veterinarian if fever remains high for more than one day.',
      ),
      _GuideSection(
        title: 'CBPP',
        subtitle: 'Contagious Bovine Pleuropneumonia',
        symptoms: const ['Coughing', 'Breathing difficulty', 'Fever', 'Weakness'],
        prevention: const [
          'Improve barn ventilation.',
          'Separate symptomatic animals.',
          'Maintain local vaccination guidance.',
        ],
        whenToCallVet:
            'Call your veterinarian urgently for breathing issues or chest pain signs.',
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Learn')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _PhotoGuideCard(),
          const SizedBox(height: 16),
          ...guides.map((guide) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _GuideCard(section: guide),
            );
          }),
          const SizedBox(height: 4),
          const _FlashcardTipCard(),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard({required this.section});

  final _GuideSection section;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            section.title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ),
        title: Text(
          section.subtitle,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('Educational guidance only'),
        children: [
          _GuideList(title: 'Common symptoms', items: section.symptoms),
          const SizedBox(height: 10),
          _GuideList(title: 'Prevention tips', items: section.prevention),
          const SizedBox(height: 10),
          Text(
            'When to call a vet',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(section.whenToCallVet, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _GuideList extends StatelessWidget {
  const _GuideList({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        ...items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.circle, size: 8),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item)),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _PhotoGuideCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How to take a good photo',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'Use daylight, keep focus on visible lesions, and keep the animal centered. Take at least 2 angles if confidence is low.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                Chip(label: Text('Daylight')),
                Chip(label: Text('Steady camera')),
                Chip(label: Text('Clean lens')),
                Chip(label: Text('2-3 angles')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FlashcardTipCard extends StatelessWidget {
  const _FlashcardTipCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.quiz_outlined),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Quick quiz mode',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Challenge: identify likely disease patterns from symptom combinations during training sessions.',
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) => const _QuizDialog(),
                  );
                },
                child: const Text('Start Quiz'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideSection {
  const _GuideSection({
    required this.title,
    required this.subtitle,
    required this.symptoms,
    required this.prevention,
    required this.whenToCallVet,
  });

  final String title;
  final String subtitle;
  final List<String> symptoms;
  final List<String> prevention;
  final String whenToCallVet;
}

class _QuizQuestion {
  const _QuizQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndex,
    required this.explanation,
  });

  final String prompt;
  final List<String> options;
  final int correctIndex;
  final String explanation;
}

class _QuizDialog extends StatefulWidget {
  const _QuizDialog();

  @override
  State<_QuizDialog> createState() => _QuizDialogState();
}

class _QuizDialogState extends State<_QuizDialog> {
  static const _questions = <_QuizQuestion>[
    _QuizQuestion(
      prompt: 'Fever + skin nodules most strongly suggests:',
      options: ['FMD', 'LSD', 'ECF', 'CBPP'],
      correctIndex: 1,
      explanation: 'Skin nodules with fever are a key warning pattern for LSD.',
    ),
    _QuizQuestion(
      prompt: 'Mouth lesions + lameness most likely indicates:',
      options: ['FMD', 'LSD', 'Normal', 'CBPP'],
      correctIndex: 0,
      explanation: 'Oral lesions and lameness commonly align with FMD.',
    ),
    _QuizQuestion(
      prompt: 'Which action is best when severe breathing difficulty appears?',
      options: [
        'Wait 2-3 days and retest',
        'Immediately isolate and call a veterinarian',
        'Only track temperature',
        'Ignore if appetite is normal',
      ],
      correctIndex: 1,
      explanation: 'Breathing distress is urgent and needs immediate veterinary attention.',
    ),
  ];

  int _index = 0;
  int _score = 0;
  int? _selectedIndex;
  bool _submitted = false;

  @override
  Widget build(BuildContext context) {
    final done = _index >= _questions.length;
    return AlertDialog(
      title: Text(done ? 'Quiz Complete' : 'Quick Quiz ${_index + 1}/${_questions.length}'),
      content: done ? _buildResult() : _buildQuestion(),
      actions: done
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                onPressed: _restart,
                child: const Text('Try Again'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Exit'),
              ),
              FilledButton(
                onPressed: _submitted ? _next : _submit,
                child: Text(_submitted ? 'Next' : 'Submit'),
              ),
            ],
    );
  }

  Widget _buildQuestion() {
    final q = _questions[_index];
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(q.prompt, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...List.generate(q.options.length, (i) {
            final selected = _selectedIndex == i;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: _submitted ? null : () => setState(() => _selectedIndex = i),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).dividerColor,
                    ),
                    color: selected
                        ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(q.options[i])),
                    ],
                  ),
                ),
              ),
            );
          }),
          if (_submitted) ...[
            const SizedBox(height: 8),
            Text(
              _selectedIndex == q.correctIndex ? 'Correct.' : 'Incorrect.',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: _selectedIndex == q.correctIndex ? const Color(0xFF1D6A3E) : Colors.red,
              ),
            ),
            const SizedBox(height: 4),
            Text(q.explanation),
          ],
        ],
      ),
    );
  }

  Widget _buildResult() {
    final total = _questions.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Score: $_score / $total', style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(
          _score == total
              ? 'Excellent. You identified all key field patterns.'
              : _score >= 2
              ? 'Good job. Review one section and retake.'
              : 'Review the disease cards and retake the quiz.',
        ),
      ],
    );
  }

  void _submit() {
    if (_selectedIndex == null) {
      return;
    }
    final q = _questions[_index];
    if (_selectedIndex == q.correctIndex) {
      _score += 1;
    }
    setState(() => _submitted = true);
  }

  void _next() {
    setState(() {
      _index += 1;
      _selectedIndex = null;
      _submitted = false;
    });
  }

  void _restart() {
    setState(() {
      _index = 0;
      _score = 0;
      _selectedIndex = null;
      _submitted = false;
    });
  }
}
