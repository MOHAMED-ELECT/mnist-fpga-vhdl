-- controller_fsm_n.vhd
-- Generalisation de controller_fsm.vhd (etape 3) au parallelisme spatial :
-- au lieu de traiter les N_HIDDEN neurones un par un, on les traite par
-- GROUPES de N_MAC neurones, calcules EN PARALLELE par N_MAC unites MAC
-- (une voie = un neurone du groupe courant). N_MAC=1 redonne exactement
-- le comportement de controller_fsm.vhd (meme nombre de cycles).
--
-- Principe (etape 5 du plan) :
--   - Toutes les voies partagent la MEME entree x(i) au meme cycle (un
--     seul port de lecture sur image_ram/act_ram, via in_addr/in_data
--     EXTERNE a ce fichier) : c'est pour ca que les N_MAC voies doivent
--     rester SYNCHRONISEES sur le meme i, donc charger leur biais au
--     MEME cycle (pas de decalage entre voies).
--   - Chaque voie lit en revanche un poids et un biais DIFFERENTS
--     (son neurone) : d'ou N_MAC adresses/donnees paralleles (w_addr,
--     b_addr -- voir weight_rom_n.vhd).
--   - La boucle MAC_LOOP dure N_IN cycles PAR GROUPE (pipelinee comme
--     dans controller_fsm.vhd), quel que soit N_MAC : c'est le nombre de
--     GROUPES (ceil(N_HIDDEN/N_MAC)) qui diminue avec N_MAC, d'ou le gain
--     ~proportionnel a N (Figure 7 du plan).
--   - L'ecriture des resultats (WRITE_LANE) est serialisee, une voie a la
--     fois : un seul bloc relu_requant est partage entre les N_MAC voies
--     (voir mac_array.vhd), ce qui evite de dupliquer SON multiplieur
--     interne. Cout : N_MAC cycles de plus par groupe, negligeable
--     devant les N_IN cycles de la boucle MAC.
--   - Dernier groupe partiel (N_HIDDEN non multiple de N_MAC, ou N_MAC >
--     N_HIDDEN comme la couche 2 avec N_MAC=16 ou 32) : les voies
--     "hors-limite" calculent quand meme (adresse bidon mais valide,
--     pour rester dans les bornes des ROM), mais leur ecriture est
--     masquee (out_we desactive pour ces voies-la dans WRITE_LANE).

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.parallel_pkg.all;

entity controller_fsm_n is
  generic (
    N_IN     : positive;      -- nombre d'entrees de la couche
    N_HIDDEN : positive;      -- nombre de neurones de la couche
    N_MAC    : positive       -- nombre d'unites MAC en parallele
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;                         -- impulsion : demarre le calcul
    busy  : out std_logic;
    done  : out std_logic;                          -- impulsion : couche terminee

    in_addr : out natural range 0 to N_IN - 1;      -- partage par toutes les voies

    w_addr : out addr_array_t(0 to N_MAC - 1);      -- une adresse de poids par voie
    b_addr : out addr_array_t(0 to N_MAC - 1);      -- une adresse de biais par voie

    mac_clear : out std_logic_vector(0 to N_MAC - 1);
    mac_en    : out std_logic_vector(0 to N_MAC - 1);

    sel_lane : out natural range 0 to N_MAC - 1;    -- voie lue par le relu_requant partage

    out_we   : out std_logic;
    out_addr : out natural range 0 to N_HIDDEN - 1
  );
end entity controller_fsm_n;

architecture rtl of controller_fsm_n is

  type state_t is (IDLE, LOAD_BIAS, LOAD_BIAS_WAIT, MAC_LOOP,
                    WRITE_LANE, NEXT_GROUP, DONE_ST);
  signal state, next_state : state_t := IDLE;

  constant N_GROUPS : positive := (N_HIDDEN + N_MAC - 1) / N_MAC;  -- ceil(N_HIDDEN/N_MAC)

  signal g, g_next   : natural range 0 to N_GROUPS - 1 := 0;  -- groupe courant
  signal i, i_next   : natural range 0 to N_IN - 1     := 0;  -- entree courante (boucle MAC)
  signal wl, wl_next : natural range 0 to N_MAC - 1    := 0;  -- voie courante (ecriture)

  type j_array_t is array (0 to N_MAC - 1) of natural range 0 to N_HIDDEN - 1;

begin

  -- ------------------------------------------------------------ registres --
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        g     <= 0;
        i     <= 0;
        wl    <= 0;
      else
        state <= next_state;
        g     <= g_next;
        i     <= i_next;
        wl    <= wl_next;
      end if;
    end if;
  end process;

  -- ------------------------------------------------- logique combinatoire --
  process (state, g, i, wl, start)
    variable j_clamped : j_array_t;  -- indice de neurone par voie, sature a
                                      -- N_HIDDEN-1 pour les voies hors-limite
                                      -- du dernier groupe (adresse valide,
                                      -- mais jamais ecrite -- voir out_we)
  begin
    for l in 0 to N_MAC - 1 loop
      if g * N_MAC + l <= N_HIDDEN - 1 then
        j_clamped(l) := g * N_MAC + l;
      else
        j_clamped(l) := N_HIDDEN - 1;
      end if;
    end loop;

    next_state <= state;
    g_next     <= g;
    i_next     <= i;
    wl_next    <= wl;

    busy <= '1';
    done <= '0';

    for l in 0 to N_MAC - 1 loop
      mac_clear(l) <= '0';
      mac_en(l)    <= '0';
      b_addr(l)    <= j_clamped(l);
      w_addr(l)    <= 0;
    end loop;

    in_addr  <= 0;
    sel_lane <= 0;
    out_we   <= '0';
    out_addr <= 0;

    case state is

      when IDLE =>
        busy   <= '0';
        g_next <= 0;
        if start = '1' then
          next_state <= LOAD_BIAS;
        end if;

      when LOAD_BIAS =>
        -- b_addr(l) deja pilote ci-dessus (valeur par defaut)
        next_state <= LOAD_BIAS_WAIT;

      when LOAD_BIAS_WAIT =>
        for l in 0 to N_MAC - 1 loop
          mac_clear(l) <= '1';          -- b_data(l) valide : charge le biais de la voie l
          -- precharge le poids i=0 de chaque voie
          w_addr(l) <= 0 * N_HIDDEN + j_clamped(l);
        end loop;
        i_next     <= 0;
        in_addr    <= 0;
        next_state <= MAC_LOOP;

      when MAC_LOOP =>
        for l in 0 to N_MAC - 1 loop
          mac_en(l) <= '1';             -- in_data/w_data(l) valides (prechargees)
        end loop;
        if i < N_IN - 1 then
          in_addr <= i + 1;
          for l in 0 to N_MAC - 1 loop
            w_addr(l) <= (i + 1) * N_HIDDEN + j_clamped(l);
          end loop;
          i_next     <= i + 1;
          next_state <= MAC_LOOP;
        else
          wl_next    <= 0;
          next_state <= WRITE_LANE;
        end if;

      when WRITE_LANE =>
        sel_lane <= wl;
        -- relu_requant (partage, combinatoire) lit mac_acc(wl) ce cycle ;
        -- son resultat est deja valide ici
        if g * N_MAC + wl <= N_HIDDEN - 1 then
          out_we   <= '1';
          out_addr <= g * N_MAC + wl;
        end if;
        -- s'arrete des que la derniere voie VALIDE du groupe est ecrite,
        -- plutot que de toujours boucler N_MAC fois : utile quand N_MAC
        -- depasse le nombre de neurones restants (ex. couche 2, N_MAC=32,
        -- seulement 10 neurones -- on ecrit 10 voies, pas 32).
        if wl < N_MAC - 1 and g * N_MAC + wl < N_HIDDEN - 1 then
          wl_next    <= wl + 1;
          next_state <= WRITE_LANE;
        else
          next_state <= NEXT_GROUP;
        end if;

      when NEXT_GROUP =>
        if g = N_GROUPS - 1 then
          next_state <= DONE_ST;
        else
          g_next     <= g + 1;
          next_state <= LOAD_BIAS;
        end if;

      when DONE_ST =>
        done       <= '1';
        next_state <= IDLE;

    end case;
  end process;

end architecture rtl;
