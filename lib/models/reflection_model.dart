part of 'index.dart';

@collection
class ReflectionModel {
  Id id = Isar.autoIncrement;

  late String name;

  late String prompt;

  DateTime createdAt = DateTime.now();

  List<ReflectionQuestion> questions = [];

  @Backlink(to: 'model')
  IsarLinks<Reflection> links = IsarLinks<Reflection>();

  static final Logger logger = Logger('ReflectionModel');

  static Future<ReflectionModel> create({
    required String name,
    required String prompt,
    List<ReflectionQuestion>? questions,
    Isar? isar,
  }) async {
    isar ??= GetIt.I<Isar>();
    final model = ReflectionModel();
    model.prompt = prompt;
    model.name = name;
    model.questions = questions ?? [];
    final modelId =
        await isar.writeTxn(() => isar!.reflectionModels.put(model));
    model.id = modelId;
    return model;
  }

  Future<File> exportToPdf(String path) async {
    throw UnimplementedError();
  }

  Future<File> exportToMarkdown(String path) async {
    await links.load();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await file.create(recursive: true);
    final writer = StringBuffer();
    writer.writeln('# $name');
    writer.writeln();
    for (int i = 0; i < links.length; i++) {
      final reflection = links.toList()[i];
      // format the date
      writer.writeln('### Reflection for Week ${i + 1}');
      final date = DateFormat('yyyy-MM-dd').format(reflection.createdAt);
      writer.writeln();
      writer.writeln('**Date**: $date\t\t**Author**: #YOUR_NAME_HERE#');
      writer.writeln();
      for (int j = 0; j < questions.length; j++) {
        if (j >= reflection.answers.length) {
          break;
        }
        final question = questions[j];
        writer.write('##### Question ${j + 1}. ${question.displayText}');
        writer.writeln();
        writer.writeln(reflection.answers[j]);
        writer.writeln();
      }
    }
    await file.writeAsString(writer.toString());
    return file;
  }

  Future<Reflection> newReflection({
    Isar? isar,
    OpenAiGenerator? generator,
    DateTime? createdAt,
    ValueNotifier<(int, int)?>? progressNotifier,
  }) async {
    isar ??= GetIt.I<Isar>();
    final reflection =
        await Reflection.create(isar: isar, createdAt: createdAt);
    reflection.model.value = this;
    await isar.writeTxn(() => reflection.model.save());
    generator ??= GetIt.I<OpenAiGenerator>();
    final openAi = generator.getOrCrash();
    final messages = [
      Messages(
        role: Role.system,
        content: prompt,
      ),
      ...await _getAllMessages(besides: reflection.id),
    ];
    progressNotifier?.value = (0, questions.length);
    for (int i = 0; i < questions.length; i++) {
      final question = questions[i];
      messages.addAll(question.messages);
      final request = ChatCompleteText(
        model: GptTurbo16k0631Model(),
        messages: messages,
        maxToken: null,
      );
      final response = await openAi.onChatCompletion(request: request);
      final answer = response?.choices.first.message?.content;
      if (answer != null) {
        logger.info(
            'Got answer for the ${i + 1}th question "$question": \n\t$answer');
        reflection.answers.add(answer);
        messages.add(Messages(role: Role.assistant, content: answer));
      } else {
        logger.warning('No answer for ${i + 1} question "$question"');
        reflection.answers.add('');
        messages.add(Messages(role: Role.assistant, content: ''));
      }
      progressNotifier?.value = (i + 1, questions.length);
    }
    logger
        .info('Got data from GPT, saving reflection with id ${reflection.id}');
    await isar.writeTxn(() => isar!.reflections.put(reflection));
    progressNotifier?.value = null;
    return reflection;
  }

  static Future<List<ReflectionModel>> load({Isar? isar}) async {
    isar ??= GetIt.I<Isar>();
    return isar.reflectionModels.where().sortByCreatedAt().findAll();
  }

  Future<List<Messages>> _getAllMessages({required int besides}) async {
    final res = <Messages>[];
    await links.load();
    for (int i = 0; i < links.length; i++) {
      final reflection = links.toList()[i];
      // if (reflection.id == besides) {
      //   continue;
      // }
      // format the date
      final date = DateFormat('yyyy-MM-dd').format(reflection.createdAt);
      res.add(
        Messages(
          role: Role.assistant,
          content: 'You are now writing for $date, the ${i + 1} th reflection',
        ),
      );
      res.addAll(_getMessagesForReflection(reflection));
    }
    return res;
  }

  List<Messages> _getMessagesForReflection(Reflection reflection) {
    final res = <Messages>[];
    for (int i = 0; i < questions.length; i++) {
      if (i >= reflection.answers.length) {
        break;
      }
      final question = questions[i];
      res.addAll(question.messages);
      final answer = reflection.answers[i];
      res.add(Messages(role: Role.assistant, content: answer));
    }
    return res;
  }

  Future<bool> canAddQuestion() async {
    await links.load();
    return links.isEmpty;
  }
}
