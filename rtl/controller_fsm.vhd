-- controller_fsm.vhd
-- Machine a etats qui pilote le calcul d'une couche complete : parcourt les
-- N_HIDDEN neurones et, pour chacun, les N_IN entrees, en generant les
-- adresses et les signaux de controle du MAC et de l'ecriture des
-- activations (Figure 5 du plan).
--
-- Piege classique : les memoires (ROM/RAM) sont a lecture synchrone, donc
-- la donnee a une adresse n'est valide qu'un cycle APRES avoir presente
-- cette adresse. Pour eviter de "perdre" un cycle par MAC (une adresse,
-- puis le calcul), la boucle MAC_LOOP est pipelinee : pendant qu'on
-- applique le produit pour l'entree i (mac_en, avec les donnees
-- prechargees au cycle precedent), on presente DEJA l'adresse de
-- l'entree i+1. Ainsi la boucle dure exactement N_IN cycles, comme
-- l'indique la Figure 5 du plan ("784 cycles en couche 1, 32 en couche 2").

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity controller_fsm is
  generic (
    N_IN     : positive;      -- nombre d'entrees de la couche
    N_HIDDEN : positive       -- nombre de neurones de la couche
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    start : in  std_logic;                         -- impulsion : demarre le calcul
    busy  : out std_logic;
    done  : out std_logic;                          -- impulsion : couche terminee

    in_addr : out natural range 0 to N_IN - 1;
    w_addr  : out natural range 0 to N_IN * N_HIDDEN - 1;
    b_addr  : out natural range 0 to N_HIDDEN - 1;

    mac_clear : out std_logic;
    mac_en    : out std_logic;

    out_we   : out std_logic;
    out_addr : out natural range 0 to N_HIDDEN - 1
  );
end entity controller_fsm;

architecture rtl of controller_fsm is

  type state_t is (IDLE, LOAD_BIAS, LOAD_BIAS_WAIT, MAC_LOOP,
                    REQUANT, WRITE_ACT, NEXT_NEURON, DONE_ST);
  signal state, next_state : state_t := IDLE;

  signal j, j_next : natural range 0 to N_HIDDEN - 1 := 0;
  signal i, i_next : natural range 0 to N_IN - 1     := 0;

begin

  -- ------------------------------------------------------------ registres --
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state <= IDLE;
        j     <= 0;
        i     <= 0;
      else
        state <= next_state;
        j     <= j_next;
        i     <= i_next;
      end if;
    end if;
  end process;

  -- ------------------------------------------------- logique combinatoire --
  process (state, j, i, start)
  begin
    next_state <= state;
    j_next     <= j;
    i_next     <= i;

    busy      <= '1';
    done      <= '0';
    mac_clear <= '0';
    mac_en    <= '0';
    out_we    <= '0';

    in_addr  <= 0;
    w_addr   <= 0;
    b_addr   <= 0;
    out_addr <= 0;

    case state is

      when IDLE =>
        busy   <= '0';
        j_next <= 0;
        if start = '1' then
          next_state <= LOAD_BIAS;
        end if;

      when LOAD_BIAS =>
        b_addr     <= j;
        next_state <= LOAD_BIAS_WAIT;

      when LOAD_BIAS_WAIT =>
        mac_clear  <= '1';    -- b_data est valide : on charge le biais
        i_next     <= 0;
        -- precharge l'entree i=0 : adresse presentee ce cycle, donnee
        -- valide au cycle suivant (premiere iteration de MAC_LOOP)
        in_addr    <= 0;
        w_addr     <= 0 * N_HIDDEN + j;
        next_state <= MAC_LOOP;

      when MAC_LOOP =>
        -- applique le produit pour l'entree i : in_data/w_data ont ete
        -- prechargees au cycle precedent (LOAD_BIAS_WAIT pour i=0, ou
        -- l'iteration precedente de MAC_LOOP pour i>0)
        mac_en <= '1';
        if i < N_IN - 1 then
          -- pendant qu'on calcule i, on precharge deja i+1
          in_addr    <= i + 1;
          w_addr     <= (i + 1) * N_HIDDEN + j;   -- aplatissement ligne-major
                                                    -- (C order) de W(N_IN,N_HIDDEN),
                                                    -- comme le fait gen_vhdl_pkg.py
          i_next     <= i + 1;
          next_state <= MAC_LOOP;
        else
          next_state <= REQUANT;
        end if;

      when REQUANT =>
        -- relu_requant est combinatoire : son resultat est deja valide ici
        next_state <= WRITE_ACT;

      when WRITE_ACT =>
        out_we     <= '1';
        out_addr   <= j;
        next_state <= NEXT_NEURON;

      when NEXT_NEURON =>
        if j = N_HIDDEN - 1 then
          next_state <= DONE_ST;
        else
          j_next     <= j + 1;
          next_state <= LOAD_BIAS;
        end if;

      when DONE_ST =>
        done       <= '1';
        next_state <= IDLE;

    end case;
  end process;

end architecture rtl;
