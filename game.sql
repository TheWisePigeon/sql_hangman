create table words (
  word text not null
);

INSERT INTO words (word) VALUES
('apple'),
('banana'),
('cat'),
('dog'),
('elephant'),
('fish'),
('grape'),
('house'),
('xenophobia'),
('jacket');

create table games (
  id serial primary key,
  word_to_guess text not null,
  number_of_letters integer not null default 0,
  finished bool not null default false
);

create table guesses (
  id serial primary key,
  guess text not null,
  is_right bool not null,
  game_id integer not null references games(id)
);

CREATE OR REPLACE FUNCTION start_game()
RETURNS TABLE(game_id INTEGER, number_of_letters INTEGER) AS $$
DECLARE 
  new_game_id INTEGER;
  random_word TEXT;
  word_length INTEGER;
BEGIN
  SELECT word INTO random_word FROM words ORDER BY RANDOM() LIMIT 1;
  INSERT INTO games(word_to_guess)
  VALUES(random_word)
  RETURNING id INTO new_game_id;
  SELECT LENGTH(random_word) INTO word_length;
  UPDATE games SET number_of_letters = word_length WHERE id = new_game_id;
  RETURN QUERY SELECT new_game_id, word_length;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION insert_guess(guessed_letter TEXT, is_right BOOL, current_game_id INTEGER)
RETURNS void as $$
BEGIN
  IF (SELECT COUNT(*) FROM guesses g WHERE g.guess = guessed_letter AND g.game_id = current_game_id) = 0 THEN
    INSERT INTO guesses(guess, is_right, game_id) VALUES(guessed_letter, is_right, current_game_id);
  END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION get_occurences(word TEXT, guessed_letter TEXT)
RETURNS INTEGER[] AS $$
DECLARE
  word_length INTEGER;
  positions INTEGER[] DEFAULT '{}';
  i INTEGER;
BEGIN
  word_length := LENGTH(word);
  FOR i in 1..word_length LOOP
    IF SUBSTRING(word FROM i FOR 1) = guessed_letter THEN
      positions := positions || i;
    END IF;
  END LOOP;
  RETURN positions;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION process_guess(guessed_letter TEXT, game_id INTEGER)
RETURNS TABLE(wrong_guesses INTEGER, game_state bool, guess_positions INTEGER[], word_to_guess TEXT, already_guessed TEXT[]) AS $$
DECLARE 
  current_game RECORD;
  guess_is_right BOOL;
  wrong_guesses_count INTEGER DEFAULT 0;
  game_is_finished BOOl DEFAULT false;
  word_to_guess TEXT DEFAULT '';
  positions INTEGER[] DEFAULT '{}';
  right_guesses INTEGER DEFAULT 0;
  already_guessed_letters TEXT[] DEFAULT '{}';
  letter TEXT;
BEGIN
  SELECT * INTO current_game FROM games where id = game_id;
  IF position(guessed_letter IN current_game.word_to_guess) > 0 THEN
    guess_is_right := true;
    PERFORM insert_guess(guessed_letter, guess_is_right, game_id);
    SELECT get_occurences(current_game.word_to_guess, guessed_letter) into positions;
    SELECT COUNT(*) INTO wrong_guesses_count FROM guesses g where g.game_id = current_game.id AND g.is_right = false;
    SELECT COUNT(*) INTO right_guesses FROM guesses g where g.game_id = current_game.id AND g.is_right = true;
    word_to_guess := current_game.word_to_guess;
    SELECT ARRAY_AGG(guess) AS guessed_letters FROM guesses g where g.game_id = current_game.id INTO already_guessed_letters;
    FOREACH letter IN ARRAY already_guessed_letters
    LOOP
      word_to_guess := REPLACE(word_to_guess, letter, '');
    END LOOP;
    IF word_to_guess = '' THEN
      UPDATE games SET finished = true WHERE id = current_game.id;
      game_is_finished := true;
    END IF;
  ELSE
    guess_is_right := false;
    PERFORM insert_guess(guessed_letter, guess_is_right, game_id);
    SELECT COUNT(*) INTO wrong_guesses_count FROM guesses g where g.game_id = current_game.id AND g.is_right = false;
    IF wrong_guesses_count = 7 THEN
      UPDATE games SET finished = true WHERE id = current_game.id;
      game_is_finished := true;
      word_to_guess := current_game.word_to_guess;
    ELSE
      game_is_finished := false;
    END IF;
  END IF;
  SELECT ARRAY_AGG(guess) AS guessed_letters FROM guesses g where g.game_id = current_game.id INTO already_guessed_letters;
  RETURN QUERY SELECT wrong_guesses_count, game_is_finished, positions, word_to_guess, already_guessed_letters;
END;
$$ LANGUAGE plpgsql;
