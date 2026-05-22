-- Domain (dog adoption) and Spring Security JDBC tables. Framework-owned tables
-- (vector_store, spring_ai_chat_memory) are intentionally left to Spring AI's
-- own initializers in the running app.

create table dog (
    id          integer       not null,
    name        text          not null,
    description text          not null,
    dob         date          not null,
    owner       text,
    gender      character(1)  not null default 'f',
    image       text          not null,
    constraint dog_pkey primary key (id)
);

create sequence dog_id_seq
    as integer
    start with 1
    increment by 1
    no minvalue
    no maxvalue
    cache 1
    owned by dog.id;

alter table dog alter column id set default nextval('dog_id_seq');

create table users (
    username text    not null,
    password text    not null,
    enabled  boolean not null,
    constraint users_pkey primary key (username)
);

create table authorities (
    username  text not null,
    authority text not null,
    constraint fk_authorities_users foreign key (username) references users (username)
);

create unique index ix_auth_username on authorities (username, authority);

-- Demo users. All three log in with password "password". Hashes are bcrypt
-- because Spring Security 7.x dropped {sha256} from the default DelegatingPasswordEncoder.
insert into users (username, password, enabled) values
    ('james', '{bcrypt}$2y$10$YVyaPWhFGJ0ENpesPJttreg2dQrU/zugChwSXR/8ZqZ1LNiALLTsK', true),
    ('rob',   '{bcrypt}$2y$10$YVyaPWhFGJ0ENpesPJttreg2dQrU/zugChwSXR/8ZqZ1LNiALLTsK', true),
    ('josh',  '{bcrypt}$2a$10$AZP7caqON.QnI0a2pgzHJOEWeEMdSqfI/kNI7kGQh3eKOzCgg9xeS',                  true);

insert into authorities (username, authority) values
    ('james', 'ROLE_ADMIN'),
    ('james', 'ROLE_USER'),
    ('josh',  'ROLE_USER'),
    ('rob',   'ROLE_USER'),
    ('rob',   'ROLE_ADMIN');

insert into dog (id, name, description, dob, owner, gender, image) values
    ( 97, 'Rocky',   'A brown Chihuahua known for being protective.',                                                                                  '2019-01-28', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/chihuahua-1.png'),
    ( 87, 'Bailey',  'A tan Dachshund known for being playful.',                                                                                       '2022-03-22', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/dachshund-1.png'),
    ( 89, 'Charlie', 'A black Bulldog known for being curious.',                                                                                       '2021-08-26', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/bulldog-1.png'),
    ( 67, 'Cooper',  'A tan Boxer known for being affectionate.',                                                                                      '2011-12-22', null,    'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/boxer-1.png'),
    ( 73, 'Max',     'A brindle Dachshund known for being energetic.',                                                                                 '2021-12-07', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/dachshund-1.png'),
    (  3, 'Buddy',   'A Poodle known for being calm.',                                                                                                 '2013-10-30', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/poodle-1.png'),
    ( 93, 'Duke',    'A white German Shepherd known for being friendly.',                                                                              '2017-03-19', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/german-shepard-2.png'),
    ( 63, 'Jasper',  'A grey Shih Tzu known for being protective.',                                                                                    '2016-01-05', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/shih-tzu-2.png'),
    ( 69, 'Toby',    'A grey Doberman known for being playful.',                                                                                       '2008-12-31', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/doberman-1.png'),
    (101, 'Nala',    'A spotted German Shepherd known for being loyal.',                                                                               '2020-07-30', null,    'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/german-shepard-1.png'),
    ( 61, 'Penny',   'A white Great Dane known for being protective.',                                                                                 '2014-05-07', null,    'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/great-dane-1.png'),
    (  1, 'Bella',   'A golden Poodle known for being calm.',                                                                                          '2020-01-07', null,    'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/poodle-2.png'),
    ( 91, 'Willow',  'A brindle Great Dane known for being calm.',                                                                                     '2011-11-15', null,    'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/great-dane-2.png'),
    (  5, 'Daisy',   'A spotted Poodle known for being affectionate.',                                                                                 '2021-07-31', null,    'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/poodle-1.png'),
    ( 45, 'Prancer', 'A demonic, neurotic, man hating, animal hating, children hating dogs that look like gremlins.',                                  '2008-12-19', null,    'm', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/prancer.jpg'),
    ( 65, 'Ruby',    'A white Great Dane known for being protective.',                                                                                 '2021-11-07', 'josh',  'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/great-dane-3.png'),
    ( 71, 'Molly',   'A golden Chihuahua known for being curious.',                                                                                    '2014-03-22', 'james', 'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/chihuahua-2.png'),
    ( 95, 'Mia',     'A grey Great Dane known for being loyal.',                                                                                       '2020-11-03', 'james', 'f', 'https://raw.githubusercontent.com/joshlong-attic/dog-images/main/great-dane-2.png');

-- Advance the sequence past the seeded ids so app-generated inserts don't collide.
select setval('dog_id_seq', (select max(id) from dog));

-- Cross-binding grants. The Tanzu postgres broker issues a distinct database user per
-- `cf bind-service` invocation; Flyway runs as the agent's user (which becomes the owner),
-- but the auth app's user is a different role and would otherwise get
--   "ERROR: permission denied for table users"
-- when JdbcUserDetailsManager tries to authenticate. Grant the user-owned tables to PUBLIC.
grant select, insert, update, delete on table users, authorities, dog to public;
grant usage, select on all sequences in schema public to public;
