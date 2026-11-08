-- controller_fsm.vhd
-- Machine a etats qui pilote le calcul d'une couche complete : parcourt les
-- N_HIDDEN neurones et, pour chacun, les N_IN entrees, en generant les
-- adresses et les signaux de controle du MAC et de l'ecriture des
-- activations (Figure 5 du plan).
--
-- Piege classique : les memoires (ROM/RAM) sont a lecture synchrone, donc
-- la donnee a une adresse n'est valide qu'un cycle APRES avoir presente
-- cette adresse. Les etats *_WAIT / *_ADDR ci-dessous existent pour
-- absorber ce decalage d'un cycle (on presente l'adresse un cycle, on
-- utilise la donnee le cycle suivant).

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

  type state_t is (IDLE, LOAD_BIAS, LOAD_BIAS_WAIT, MAC_ADDR, MAC_APPLY,
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
        mac_clear  <= '1';            -- b_data est valide : on charge le biais
        i_next     <= 0;
        next_state <= MAC_ADDR;

      when MAC_ADDR =>
        in_addr    <= i;
        w_addr     <= i * N_HIDDEN + j;   -- doit correspondre a l'aplatissement
                                            -- ligne-major (C order) de W(N_IN,N_HIDDEN)
                                            -- fait par gen_vhdl_pkg.py
        next_state <= MAC_APPLY;

      when MAC_APPLY =>
        mac_en <= '1';                -- in_data/w_data sont valides
        if i = N_IN - 1 then
          next_state <= REQUANT;
        else
          i_next     <= i + 1;
          next_state <= MAC_ADDR;
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
