import 'package:atlas_mobile/features/grading/course_exam_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('numbered questions with choice lines and Answer lines', () {
    final items = parseExamQuestions('''
1. What is 2 + 2?
A. 3
B. 4
C. 5
D. 6
Answer: B

2) Which is a mammal
that lives in the sea?
a) Shark
b) Whale
c) Tuna
Ans: b
''');
    expect(items.length, 2);
    expect(items[0].question, 'What is 2 + 2?');
    expect(items[0].choices, ['3', '4', '5', '6']);
    expect(items[0].answer, 'B');
    expect(items[1].question, 'Which is a mammal that lives in the sea?');
    expect(items[1].choices, ['Shark', 'Whale', 'Tuna']);
    expect(items[1].answer, 'B');
  });

  test('inline choices and star marks', () {
    final items = parseExamQuestions('''
1. Capital of France?  A. Rome  *B. Paris  C. Madrid  D. Berlin
2. Largest planet?
A. Mars
B. Venus
C. Jupiter *
D. Earth
''');
    expect(items.length, 2);
    expect(items[0].question, 'Capital of France?');
    expect(items[0].choices, ['Rome', 'Paris', 'Madrid', 'Berlin']);
    expect(items[0].answer, 'B');
    expect(items[1].choices[2], 'Jupiter');
    expect(items[1].answer, 'C');
  });

  test('unnumbered questions split after their choices', () {
    final items = parseExamQuestions('''
Water boils at?
A. 50 C
B. 100 C
Sun is a?
A. Planet
B. Star
''');
    expect(items.length, 2);
    expect(items[1].question, 'Sun is a?');
    expect(items[1].choices, ['Planet', 'Star']);
  });

  test('answer key formats', () {
    expect(parseAnswerKey('1.B 2-c 3) A'), {1: 'B', 2: 'C', 3: 'A'});
    expect(parseAnswerKey('BA-D'), {1: 'B', 2: 'A', 4: 'D'});
    expect(parseAnswerKey('1. A\n2. B\n3. E\n4. D'), {1: 'A', 2: 'B', 4: 'D'});
  });
}
